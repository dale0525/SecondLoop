use crate::{
    bridge::responses_to_chat_completions,
    provider::{EndpointType, ProviderProfile},
    tool_identity::ToolNameMap,
};
use futures::{Stream, stream};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Value, json};
use std::pin::Pin;

pub type GatewayEventStream = Pin<Box<dyn Stream<Item = anyhow::Result<GatewayEvent>> + Send>>;

#[derive(Debug, Clone, PartialEq)]
pub struct GatewayTool {
    pub id: String,
    advertised_name: Option<String>,
    pub description: String,
    pub input_schema: Value,
}

#[derive(Serialize)]
struct SerializedGatewayTool<'a> {
    name: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<&'a str>,
    description: &'a str,
    input_schema: &'a Value,
}

#[derive(Deserialize)]
struct DeserializedGatewayTool {
    name: Option<String>,
    id: Option<String>,
    description: String,
    input_schema: Value,
}

impl Serialize for GatewayTool {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        SerializedGatewayTool {
            name: self.advertised_name(),
            id: self.advertised_name.as_ref().map(|_| self.id.as_str()),
            description: &self.description,
            input_schema: &self.input_schema,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for GatewayTool {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let tool = DeserializedGatewayTool::deserialize(deserializer)?;
        let (id, advertised_name) = match (tool.name, tool.id) {
            (Some(name), Some(id)) => (id, Some(name)),
            (Some(name), None) => (name, None),
            (None, Some(id)) => (id, None),
            (None, None) => return Err(serde::de::Error::missing_field("name or id")),
        };
        Ok(Self {
            id,
            advertised_name,
            description: tool.description,
            input_schema: tool.input_schema,
        })
    }
}

impl GatewayTool {
    pub fn new(id: impl Into<String>, description: impl Into<String>, input_schema: Value) -> Self {
        Self {
            id: id.into(),
            advertised_name: None,
            description: description.into(),
            input_schema,
        }
    }

    pub fn advertised_alias(
        id: impl Into<String>,
        advertised_name: impl Into<String>,
        description: impl Into<String>,
        input_schema: Value,
    ) -> Self {
        Self {
            id: id.into(),
            advertised_name: Some(advertised_name.into()),
            description: description.into(),
            input_schema,
        }
    }

    pub fn advertised_name(&self) -> &str {
        self.advertised_name.as_deref().unwrap_or(&self.id)
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct GatewayRequest {
    pub input: Vec<Value>,
    pub tools: Vec<GatewayTool>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum GatewayEvent {
    ResponseStarted {
        response_id: String,
    },
    TextDelta {
        text: String,
    },
    ReasoningDelta {
        text: String,
    },
    ToolCall {
        call_id: String,
        name: String,
        #[serde(default, skip_serializing_if = "is_false")]
        legacy_alias_selected: bool,
        arguments: Value,
    },
    Usage {
        input_tokens: u64,
        output_tokens: u64,
    },
    Completed,
    Error {
        message: String,
    },
}

#[derive(Debug, Clone)]
pub struct GatewayHttpClient {
    profile: ProviderProfile,
    client: reqwest::Client,
}

impl GatewayHttpClient {
    pub fn new(profile: ProviderProfile) -> Self {
        Self {
            profile,
            client: reqwest::Client::new(),
        }
    }

    pub async fn stream(&self, request: GatewayRequest) -> anyhow::Result<GatewayEventStream> {
        ensure_tool_support(&self.profile, &request.tools)?;
        let tool_map = ToolNameMap::from_tools(&request.tools)?;
        let body = gateway_request_body_with_tool_map(&self.profile, request, &tool_map)?;
        let mut builder = self.client.post(self.profile.endpoint_url()).json(&body);

        if let Some(api_key) = &self.profile.api_key
            && !api_key.trim().is_empty()
        {
            builder = builder.bearer_auth(api_key);
        }
        for (name, value) in &self.profile.headers {
            builder = builder.header(name, value);
        }

        let response = builder.send().await?;
        let status = response.status();
        if !status.is_success() {
            let url = response.url().to_string();
            let body = response.text().await.unwrap_or_else(|error| {
                format!("<failed to read upstream response body: {error}>")
            });
            anyhow::bail!("{}", upstream_error_message(status, &url, &body));
        }

        if crate::streaming_transport::is_event_stream(&response) {
            return Ok(crate::streaming_transport::into_gateway_event_stream(
                response,
                self.profile.endpoint_type,
                tool_map,
            ));
        }

        let response = response.json().await?;
        let events = parse_gateway_response_with_tool_map(&self.profile, response, &tool_map)?;

        Ok(Box::pin(stream::iter(events.into_iter().map(Ok))))
    }
}

pub fn gateway_request_body(
    profile: &ProviderProfile,
    request: GatewayRequest,
) -> anyhow::Result<Value> {
    ensure_tool_support(profile, &request.tools)?;
    let tool_map = ToolNameMap::from_tools(&request.tools)?;
    gateway_request_body_with_tool_map(profile, request, &tool_map)
}

pub fn gateway_request_body_with_tool_map(
    profile: &ProviderProfile,
    request: GatewayRequest,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Value> {
    ensure_tool_support(profile, &request.tools)?;

    match profile.endpoint_type {
        EndpointType::Responses => gateway_responses_body(&profile.model, request, tool_map),
        EndpointType::ChatCompletions => {
            responses_to_chat_completions(gateway_base_body(&profile.model, request, tool_map)?)
        }
        EndpointType::Completion => {
            let prompt = latest_text_prompt(&request.input);
            Ok(json!({
                "model": profile.model,
                "prompt": prompt,
                "stream": false,
            }))
        }
    }
}

fn ensure_tool_support(profile: &ProviderProfile, tools: &[GatewayTool]) -> anyhow::Result<()> {
    if !profile.supports_tools() && !tools.is_empty() {
        anyhow::bail!("model_endpoint_does_not_support_tools");
    }
    Ok(())
}

fn gateway_base_body(
    model: &str,
    request: GatewayRequest,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Value> {
    Ok(json!({
        "model": model,
        "input": mapped_input(request.input, tool_map)?,
        "tools": mapped_base_tools(request.tools, tool_map)?,
        "stream": true,
    }))
}

fn gateway_responses_body(
    model: &str,
    request: GatewayRequest,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Value> {
    Ok(json!({
        "model": model,
        "input": responses_input_items(mapped_input(request.input, tool_map)?),
        "tools": responses_tools(request.tools, tool_map)?,
        "stream": true,
    }))
}

fn mapped_base_tools(
    tools: Vec<GatewayTool>,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Vec<Value>> {
    tools
        .into_iter()
        .map(|tool| {
            let name = mapped_tool_wire_name(tool_map, &tool)?;
            Ok(json!({
                "name": name,
                "description": tool.description,
                "input_schema": tool.input_schema,
            }))
        })
        .collect()
}

fn responses_tools(tools: Vec<GatewayTool>, tool_map: &ToolNameMap) -> anyhow::Result<Vec<Value>> {
    tools
        .into_iter()
        .map(|tool| {
            let name = mapped_tool_wire_name(tool_map, &tool)?;
            Ok(json!({
                "type": "function",
                "name": name,
                "description": tool.description,
                "parameters": tool.input_schema,
            }))
        })
        .collect()
}

fn mapped_input(mut input: Vec<Value>, tool_map: &ToolNameMap) -> anyhow::Result<Vec<Value>> {
    for item in &mut input {
        if item.get("role").and_then(Value::as_str) == Some("assistant")
            && let Some(tool_calls) = item.get_mut("tool_calls").and_then(Value::as_array_mut)
        {
            for tool_call in tool_calls {
                let Some(name) = tool_call
                    .get_mut("function")
                    .and_then(|function| function.get_mut("name"))
                else {
                    continue;
                };
                map_history_name(name, tool_map)?;
            }
        }
        if item.get("type").and_then(Value::as_str) == Some("function_call")
            && let Some(name) = item.get_mut("name")
        {
            map_history_name(name, tool_map)?;
        }
    }
    Ok(input)
}

fn map_history_name(name: &mut Value, tool_map: &ToolNameMap) -> anyhow::Result<()> {
    let canonical = name
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("assistant tool history has invalid tool name"))?;
    *name = Value::String(
        tool_map
            .wire_name(canonical)
            .ok_or_else(|| anyhow::anyhow!("assistant tool history references unavailable tool"))?
            .to_string(),
    );
    Ok(())
}

fn mapped_tool_wire_name<'a>(
    tool_map: &'a ToolNameMap,
    tool: &GatewayTool,
) -> anyhow::Result<&'a str> {
    tool_map
        .wire_name_for_tool(tool)
        .ok_or_else(|| anyhow::anyhow!("tool definition is missing provider mapping"))
}

fn responses_input_items(input: Vec<Value>) -> Vec<Value> {
    input.into_iter().flat_map(responses_input_item).collect()
}

fn responses_input_item(item: Value) -> Vec<Value> {
    if item.get("role").and_then(Value::as_str) == Some("assistant")
        && let Some(tool_calls) = item.get("tool_calls").and_then(Value::as_array)
    {
        return tool_calls
            .iter()
            .filter_map(chat_tool_call_to_responses_function_call)
            .collect();
    }

    if item.get("role").and_then(Value::as_str) == Some("tool") {
        return vec![json!({
            "type": "function_call_output",
            "call_id": item.get("tool_call_id").cloned().unwrap_or(Value::Null),
            "output": response_tool_output(item.get("content")),
        })];
    }

    vec![item]
}

fn chat_tool_call_to_responses_function_call(tool_call: &Value) -> Option<Value> {
    let function = tool_call.get("function")?;
    Some(json!({
        "type": "function_call",
        "call_id": tool_call.get("id").cloned().unwrap_or(Value::Null),
        "name": function.get("name").cloned().unwrap_or(Value::Null),
        "arguments": function
            .get("arguments")
            .cloned()
            .unwrap_or_else(|| Value::String("{}".into())),
        "status": "completed",
    }))
}

fn response_tool_output(output: Option<&Value>) -> String {
    match output {
        Some(Value::String(text)) => text.clone(),
        Some(value) => value.to_string(),
        None => String::new(),
    }
}

fn upstream_error_message(status: reqwest::StatusCode, url: &str, body: &str) -> String {
    let body = body.trim();
    let body = if body.is_empty() { "<empty>" } else { body };
    format!("upstream model request failed: {status} for url ({url}); body: {body}")
}

pub fn parse_gateway_response(
    profile: &ProviderProfile,
    response: Value,
) -> anyhow::Result<Vec<GatewayEvent>> {
    parse_gateway_response_with_tool_map(profile, response, &ToolNameMap::from_tools(&[])?)
}

pub fn parse_gateway_response_with_tool_map(
    profile: &ProviderProfile,
    response: Value,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Vec<GatewayEvent>> {
    match profile.endpoint_type {
        EndpointType::Responses => parse_responses_response(response, tool_map),
        EndpointType::ChatCompletions => parse_chat_completion_response(response, tool_map),
        EndpointType::Completion => parse_completion_response(response),
    }
}

fn latest_text_prompt(input: &[Value]) -> String {
    input
        .iter()
        .rev()
        .find_map(|item| item.get("content"))
        .map(|content| match content {
            Value::String(text) => text.clone(),
            value => value.to_string(),
        })
        .unwrap_or_default()
}

fn parse_chat_completion_response(
    response: Value,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Vec<GatewayEvent>> {
    let mut events = Vec::new();
    let message = response
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .ok_or_else(|| anyhow::anyhow!("chat completion response missing message"))?;

    if let Some(content) = message.get("content").and_then(Value::as_str)
        && !content.is_empty()
    {
        events.push(GatewayEvent::TextDelta {
            text: content.to_string(),
        });
    }

    if let Some(tool_calls) = message.get("tool_calls").and_then(Value::as_array) {
        for tool_call in tool_calls {
            if let Some(event) = parse_chat_tool_call(tool_call, tool_map)? {
                events.push(event);
            }
        }
    }

    events.push(GatewayEvent::Completed);
    Ok(events)
}

fn parse_completion_response(response: Value) -> anyhow::Result<Vec<GatewayEvent>> {
    let text = response
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("text"))
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("completion response missing text"))?;

    Ok(vec![
        GatewayEvent::TextDelta {
            text: text.to_string(),
        },
        GatewayEvent::Completed,
    ])
}

fn parse_chat_tool_call(
    tool_call: &Value,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Option<GatewayEvent>> {
    let function = match tool_call.get("function") {
        Some(function) => function,
        None => return Ok(None),
    };
    let name = match function.get("name").and_then(Value::as_str) {
        Some(name) => name,
        None => return Ok(None),
    };
    let canonical = canonical_tool_name(tool_map, name)?;
    let call_id = tool_call
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or(name)
        .to_string();
    let arguments = parse_arguments(function.get("arguments"))?;

    Ok(Some(GatewayEvent::ToolCall {
        call_id,
        name: canonical.to_string(),
        legacy_alias_selected: selected_alias(tool_map, name, canonical),
        arguments,
    }))
}

fn parse_responses_response(
    response: Value,
    tool_map: &ToolNameMap,
) -> anyhow::Result<Vec<GatewayEvent>> {
    let mut events = Vec::new();

    if let Some(output) = response.get("output").and_then(Value::as_array) {
        for item in output {
            collect_responses_output_item(item, &mut events, tool_map)?;
        }
    }

    if !events
        .iter()
        .any(|event| matches!(event, GatewayEvent::TextDelta { .. }))
        && let Some(output_text) = response.get("output_text").and_then(Value::as_str)
        && !output_text.is_empty()
    {
        events.push(GatewayEvent::TextDelta {
            text: output_text.to_string(),
        });
    }

    events.push(GatewayEvent::Completed);
    Ok(events)
}

fn collect_responses_output_item(
    item: &Value,
    events: &mut Vec<GatewayEvent>,
    tool_map: &ToolNameMap,
) -> anyhow::Result<()> {
    match item.get("type").and_then(Value::as_str) {
        Some("function_call") => {
            let name = item
                .get("name")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow::anyhow!("responses function_call missing name"))?;
            let canonical = canonical_tool_name(tool_map, name)?;
            let call_id = item
                .get("call_id")
                .or_else(|| item.get("id"))
                .and_then(Value::as_str)
                .unwrap_or(name);
            events.push(GatewayEvent::ToolCall {
                call_id: call_id.to_string(),
                name: canonical.to_string(),
                legacy_alias_selected: selected_alias(tool_map, name, canonical),
                arguments: parse_arguments(item.get("arguments"))?,
            });
        }
        Some("message") => {
            if let Some(content) = item.get("content").and_then(Value::as_array) {
                for part in content {
                    if let Some(text) = part
                        .get("text")
                        .or_else(|| part.get("output_text"))
                        .and_then(Value::as_str)
                    {
                        events.push(GatewayEvent::TextDelta {
                            text: text.to_string(),
                        });
                    }
                }
            }
        }
        _ => {}
    }

    Ok(())
}

fn canonical_tool_name<'a>(tool_map: &'a ToolNameMap, wire: &str) -> anyhow::Result<&'a str> {
    tool_map
        .canonical_name(wire)
        .ok_or_else(|| anyhow::anyhow!("unknown provider tool name"))
}

fn selected_alias(tool_map: &ToolNameMap, wire: &str, canonical: &str) -> bool {
    tool_map
        .advertised_name(wire)
        .is_some_and(|advertised| advertised != canonical)
}

fn is_false(value: &bool) -> bool {
    !*value
}

fn parse_arguments(arguments: Option<&Value>) -> anyhow::Result<Value> {
    match arguments {
        Some(Value::String(text)) if text.trim().is_empty() => Ok(json!({})),
        Some(Value::String(text)) => Ok(serde_json::from_str(text)?),
        Some(value) => Ok(value.clone()),
        None => Ok(json!({})),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::{EndpointType, ProviderProfile};
    use std::collections::BTreeMap;

    #[test]
    fn chat_completion_tool_calls_parse_to_gateway_events() {
        let response = serde_json::json!({
            "choices": [
                {
                    "message": {
                        "tool_calls": [
                            {
                                "id": "call-1",
                                "type": "function",
                                "function": {
                                    "name": "echo",
                                    "arguments": "{\"text\":\"hello\"}"
                                }
                            }
                        ]
                    }
                }
            ]
        });

        let map = ToolNameMap::from_tools_with_test_encoder(
            &[GatewayTool::new(
                "echo",
                "Return text.",
                serde_json::json!({ "type": "object" }),
            )],
            |_| "echo".into(),
        )
        .unwrap();
        let events = parse_chat_completion_response(response, &map).unwrap();

        assert_eq!(
            events,
            vec![
                GatewayEvent::ToolCall {
                    call_id: "call-1".into(),
                    name: "echo".into(),
                    legacy_alias_selected: false,
                    arguments: serde_json::json!({ "text": "hello" }),
                },
                GatewayEvent::Completed,
            ]
        );
    }

    #[test]
    fn gateway_request_body_includes_runtime_tools_for_chat_completions() {
        let profile = ProviderProfile {
            id: "local".into(),
            name: "Local".into(),
            endpoint_type: EndpointType::ChatCompletions,
            base_url: "http://localhost:11434/v1".into(),
            model: "agent-model".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let request = GatewayRequest {
            input: vec![serde_json::json!({ "role": "user", "content": "echo hello" })],
            tools: vec![GatewayTool::new(
                "echo",
                "Return text.",
                serde_json::json!({ "type": "object" }),
            )],
        };

        let body = gateway_request_body(&profile, request).unwrap();

        assert_eq!(body["model"], "agent-model");
        let wire = body["tools"][0]["function"]["name"].as_str().unwrap();
        assert_ne!(wire, "echo");
        assert!(wire.len() <= 64);
        assert_eq!(body["stream"], true);
    }

    #[test]
    fn chat_completion_body_preserves_tool_result_messages() {
        let profile = ProviderProfile {
            id: "local".into(),
            name: "Local".into(),
            endpoint_type: EndpointType::ChatCompletions,
            base_url: "http://localhost:11434/v1".into(),
            model: "agent-model".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let request = GatewayRequest {
            input: vec![
                serde_json::json!({ "role": "user", "content": "echo hello" }),
                serde_json::json!({
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "id": "call-1",
                            "type": "function",
                            "function": {
                                "name": "echo",
                                "arguments": "{\"text\":\"hello\"}"
                            }
                        }
                    ]
                }),
                serde_json::json!({
                    "role": "tool",
                    "tool_call_id": "call-1",
                    "content": { "text": "hello" }
                }),
            ],
            tools: vec![GatewayTool::new(
                "echo",
                "Return text.",
                serde_json::json!({ "type": "object" }),
            )],
        };

        let body = gateway_request_body(&profile, request).unwrap();

        assert_eq!(body["messages"][1]["role"], "assistant");
        assert_eq!(body["messages"][1]["tool_calls"][0]["id"], "call-1");
        assert_eq!(
            body["messages"][1]["tool_calls"][0]["function"]["name"],
            body["tools"][0]["function"]["name"]
        );
        assert_eq!(body["messages"][2]["role"], "tool");
        assert_eq!(body["messages"][2]["tool_call_id"], "call-1");
        assert_eq!(body["messages"][2]["content"], "{\"text\":\"hello\"}");
    }

    #[test]
    fn gateway_request_body_includes_function_tools_for_responses() {
        let profile = ProviderProfile {
            id: "openai".into(),
            name: "OpenAI".into(),
            endpoint_type: EndpointType::Responses,
            base_url: "https://api.openai.com/v1".into(),
            model: "gpt-5.4".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let request = GatewayRequest {
            input: vec![serde_json::json!({ "role": "user", "content": "echo hello" })],
            tools: vec![GatewayTool::new(
                "echo",
                "Return text.",
                serde_json::json!({ "type": "object" }),
            )],
        };

        let body = gateway_request_body(&profile, request).unwrap();

        assert_eq!(body["tools"][0]["type"], "function");
        assert_ne!(body["tools"][0]["name"], "echo");
        assert_eq!(body["tools"][0]["parameters"]["type"], "object");
        assert_eq!(body["tools"][0]["input_schema"], Value::Null);
    }

    #[test]
    fn responses_body_converts_chat_tool_result_items_to_function_call_outputs() {
        let profile = ProviderProfile {
            id: "openai".into(),
            name: "OpenAI".into(),
            endpoint_type: EndpointType::Responses,
            base_url: "https://api.openai.com/v1".into(),
            model: "gpt-5.4".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let request = GatewayRequest {
            input: vec![
                serde_json::json!({ "role": "user", "content": "echo hello" }),
                serde_json::json!({
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "id": "call-1",
                            "type": "function",
                            "function": {
                                "name": "echo",
                                "arguments": "{\"text\":\"hello\"}"
                            }
                        }
                    ]
                }),
                serde_json::json!({
                    "role": "tool",
                    "tool_call_id": "call-1",
                    "content": { "text": "hello" }
                }),
            ],
            tools: vec![GatewayTool::new(
                "echo",
                "Return text.",
                serde_json::json!({ "type": "object" }),
            )],
        };

        let body = gateway_request_body(&profile, request).unwrap();

        assert_eq!(body["input"][1]["type"], "function_call");
        assert_eq!(body["input"][1]["call_id"], "call-1");
        assert_eq!(body["input"][1]["name"], body["tools"][0]["name"]);
        assert_eq!(body["input"][2]["type"], "function_call_output");
        assert_eq!(body["input"][2]["call_id"], "call-1");
        assert_eq!(body["input"][2]["output"], "{\"text\":\"hello\"}");
    }

    #[test]
    fn completion_response_text_parses_to_gateway_events() {
        let profile = ProviderProfile {
            id: "legacy".into(),
            name: "Legacy".into(),
            endpoint_type: EndpointType::Completion,
            base_url: "http://localhost:11434/v1".into(),
            model: "legacy-model".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let response = serde_json::json!({
            "choices": [
                { "text": "plain completion" }
            ]
        });

        let events = parse_gateway_response(&profile, response).unwrap();

        assert_eq!(
            events,
            vec![
                GatewayEvent::TextDelta {
                    text: "plain completion".into()
                },
                GatewayEvent::Completed,
            ]
        );
    }

    #[test]
    fn completion_body_rejects_tool_schemas() {
        let profile = ProviderProfile {
            id: "legacy".into(),
            name: "Legacy".into(),
            endpoint_type: EndpointType::Completion,
            base_url: "http://localhost:11434/v1".into(),
            model: "legacy-model".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let request = GatewayRequest {
            input: vec![serde_json::json!({ "role": "user", "content": "echo hello" })],
            tools: vec![GatewayTool::new(
                "echo",
                "Return text.",
                serde_json::json!({ "type": "object" }),
            )],
        };

        let error = gateway_request_body(&profile, request).unwrap_err();

        assert!(
            error
                .to_string()
                .contains("model_endpoint_does_not_support_tools")
        );
    }

    #[test]
    fn completion_body_without_tools_still_builds_prompt() {
        let profile = ProviderProfile {
            id: "legacy".into(),
            name: "Legacy".into(),
            endpoint_type: EndpointType::Completion,
            base_url: "http://localhost:11434/v1".into(),
            model: "legacy-model".into(),
            api_key: None,
            headers: BTreeMap::new(),
        };
        let request = GatewayRequest {
            input: vec![serde_json::json!({ "role": "user", "content": "plain prompt" })],
            tools: Vec::new(),
        };

        let body = gateway_request_body(&profile, request).unwrap();

        assert_eq!(body["model"], "legacy-model");
        assert_eq!(body["prompt"], "plain prompt");
        assert_eq!(body["stream"], false);
        assert_eq!(body["tools"], Value::Null);
    }

    #[test]
    fn upstream_error_message_includes_status_url_and_body() {
        let message = upstream_error_message(
            reqwest::StatusCode::BAD_REQUEST,
            "https://api.portkey.ai/v1/chat/completions",
            "{\"error\":{\"message\":\"invalid model\"}}",
        );

        assert!(message.contains("upstream model request failed"));
        assert!(message.contains("400 Bad Request"));
        assert!(message.contains("https://api.portkey.ai/v1/chat/completions"));
        assert!(message.contains("invalid model"));
    }

    #[test]
    fn responses_output_text_does_not_duplicate_message_content() {
        let response = serde_json::json!({
            "output_text": "hello",
            "output": [
                {
                    "type": "message",
                    "content": [
                        {
                            "type": "output_text",
                            "text": "hello"
                        }
                    ]
                }
            ]
        });

        let map = ToolNameMap::from_tools(&[]).unwrap();
        let events = parse_responses_response(response, &map).unwrap();

        assert_eq!(
            events,
            vec![
                GatewayEvent::TextDelta {
                    text: "hello".into()
                },
                GatewayEvent::Completed,
            ]
        );
    }
}
