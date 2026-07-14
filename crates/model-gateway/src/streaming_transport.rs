use crate::{
    provider::EndpointType,
    responses::{GatewayEvent, GatewayEventStream},
    streaming::{StreamingToolCallAssembler, ToolCallDelta},
    tool_identity::ToolNameMap,
};
use futures::StreamExt;
use serde_json::Value;
use std::collections::BTreeMap;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

const MAX_PENDING_SSE_BYTES: usize = 2 * 1024 * 1024;

pub(crate) fn is_event_stream(response: &reqwest::Response) -> bool {
    response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.to_ascii_lowercase().contains("text/event-stream"))
}

pub(crate) fn into_gateway_event_stream(
    response: reqwest::Response,
    endpoint_type: EndpointType,
    tool_map: ToolNameMap,
) -> GatewayEventStream {
    let (sender, receiver) = mpsc::channel(64);
    tokio::spawn(async move {
        let mut bytes = response.bytes_stream();
        let mut decoder = SseDecoder::default();
        let mut parser = GatewayStreamParser::new(endpoint_type, tool_map);
        loop {
            let chunk = tokio::select! {
                _ = sender.closed() => return,
                chunk = bytes.next() => chunk,
            };
            let Some(chunk) = chunk else {
                break;
            };
            let frames = match chunk
                .map_err(anyhow::Error::from)
                .and_then(|chunk| decoder.push(&chunk))
            {
                Ok(frames) => frames,
                Err(error) => {
                    let _ = sender.send(Err(error)).await;
                    return;
                }
            };
            for frame in frames {
                if !send_events(&sender, parser.push(frame)).await {
                    return;
                }
            }
        }
        match decoder.finish() {
            Ok(frames) => {
                for frame in frames {
                    if !send_events(&sender, parser.push(frame)).await {
                        return;
                    }
                }
            }
            Err(error) => {
                let _ = sender.send(Err(error)).await;
                return;
            }
        }
        let _ = send_events(&sender, parser.finish()).await;
    });
    Box::pin(ReceiverStream::new(receiver))
}

async fn send_events(
    sender: &mpsc::Sender<anyhow::Result<GatewayEvent>>,
    events: anyhow::Result<Vec<GatewayEvent>>,
) -> bool {
    match events {
        Ok(events) => {
            for event in events {
                if sender.send(Ok(event)).await.is_err() {
                    return false;
                }
            }
            true
        }
        Err(error) => {
            let _ = sender.send(Err(error)).await;
            false
        }
    }
}

#[derive(Debug)]
struct SseFrame {
    event: Option<String>,
    data: String,
}

#[derive(Default)]
struct SseDecoder {
    pending: Vec<u8>,
}

impl SseDecoder {
    fn push(&mut self, chunk: &[u8]) -> anyhow::Result<Vec<SseFrame>> {
        self.pending.extend_from_slice(chunk);
        anyhow::ensure!(
            self.pending.len() <= MAX_PENDING_SSE_BYTES,
            "streaming model event exceeds the buffer limit"
        );
        let mut frames = Vec::new();
        while let Some((position, delimiter_len)) = frame_boundary(&self.pending) {
            let frame = self.pending[..position].to_vec();
            self.pending.drain(..position + delimiter_len);
            if let Some(frame) = parse_frame(&frame)? {
                frames.push(frame);
            }
        }
        Ok(frames)
    }

    fn finish(&mut self) -> anyhow::Result<Vec<SseFrame>> {
        if self.pending.iter().all(u8::is_ascii_whitespace) {
            self.pending.clear();
            return Ok(Vec::new());
        }
        let frame = std::mem::take(&mut self.pending);
        Ok(parse_frame(&frame)?.into_iter().collect())
    }
}

fn frame_boundary(bytes: &[u8]) -> Option<(usize, usize)> {
    let lf = bytes.windows(2).position(|window| window == b"\n\n");
    let crlf = bytes.windows(4).position(|window| window == b"\r\n\r\n");
    match (lf, crlf) {
        (Some(left), Some(right)) if left <= right => Some((left, 2)),
        (Some(_), Some(right)) => Some((right, 4)),
        (Some(position), None) => Some((position, 2)),
        (None, Some(position)) => Some((position, 4)),
        (None, None) => None,
    }
}

fn parse_frame(bytes: &[u8]) -> anyhow::Result<Option<SseFrame>> {
    let text = std::str::from_utf8(bytes)?;
    let mut event = None;
    let mut data = Vec::new();
    for line in text.lines() {
        if line.starts_with(':') {
            continue;
        }
        if let Some(value) = line.strip_prefix("event:") {
            event = Some(value.trim_start().to_string());
        }
        if let Some(value) = line.strip_prefix("data:") {
            data.push(value.trim_start());
        }
    }
    if data.is_empty() {
        return Ok(None);
    }
    Ok(Some(SseFrame {
        event,
        data: data.join("\n"),
    }))
}

struct GatewayStreamParser {
    endpoint_type: EndpointType,
    tool_map: ToolNameMap,
    chat_tools: StreamingToolCallAssembler,
    response_tools: BTreeMap<usize, ResponseToolCall>,
    completed: bool,
    response_started: bool,
}

#[derive(Default)]
struct ResponseToolCall {
    call_id: Option<String>,
    name: Option<String>,
    arguments: String,
}

impl GatewayStreamParser {
    fn new(endpoint_type: EndpointType, tool_map: ToolNameMap) -> Self {
        Self {
            endpoint_type,
            tool_map,
            chat_tools: StreamingToolCallAssembler::default(),
            response_tools: BTreeMap::new(),
            completed: false,
            response_started: false,
        }
    }

    fn push(&mut self, frame: SseFrame) -> anyhow::Result<Vec<GatewayEvent>> {
        if frame.data.trim() == "[DONE]" {
            return self.complete();
        }
        let mut value: Value = serde_json::from_str(&frame.data)?;
        if value.get("type").is_none()
            && let Some(event) = frame.event
        {
            value["type"] = Value::String(event);
        }
        match self.endpoint_type {
            EndpointType::Responses => self.push_responses(&value),
            EndpointType::ChatCompletions => self.push_chat(&value),
            EndpointType::Completion => self.push_completion(&value),
        }
    }

    fn finish(&mut self) -> anyhow::Result<Vec<GatewayEvent>> {
        anyhow::ensure!(
            self.completed,
            "streaming model response ended before a terminal event"
        );
        Ok(Vec::new())
    }

    fn push_chat(&mut self, value: &Value) -> anyhow::Result<Vec<GatewayEvent>> {
        let mut events = self.started_event(value.get("id").and_then(Value::as_str));
        if let Some(usage) = value.get("usage") {
            append_usage(&mut events, usage);
        }
        let Some(choice) = value
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
        else {
            return Ok(events);
        };
        let delta = choice.get("delta").unwrap_or(&Value::Null);
        if let Some(text) = delta.get("content").and_then(Value::as_str)
            && !text.is_empty()
        {
            events.push(GatewayEvent::TextDelta { text: text.into() });
        }
        if let Some(text) = delta
            .get("reasoning_content")
            .or_else(|| delta.get("reasoning"))
            .and_then(Value::as_str)
            && !text.is_empty()
        {
            events.push(GatewayEvent::ReasoningDelta { text: text.into() });
        }
        for tool in delta
            .get("tool_calls")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let function = tool.get("function").unwrap_or(&Value::Null);
            self.chat_tools.push(ToolCallDelta {
                index: tool.get("index").and_then(Value::as_u64).unwrap_or(0) as usize,
                call_id: tool.get("id").and_then(Value::as_str).map(str::to_string),
                name: function
                    .get("name")
                    .and_then(Value::as_str)
                    .map(str::to_string),
                arguments_delta: function
                    .get("arguments")
                    .and_then(Value::as_str)
                    .map(str::to_string),
            })?;
        }
        if !choice
            .get("finish_reason")
            .unwrap_or(&Value::Null)
            .is_null()
        {
            events.extend(self.complete()?);
        }
        Ok(events)
    }

    fn push_completion(&mut self, value: &Value) -> anyhow::Result<Vec<GatewayEvent>> {
        let mut events = self.started_event(value.get("id").and_then(Value::as_str));
        if let Some(choice) = value
            .get("choices")
            .and_then(Value::as_array)
            .and_then(|choices| choices.first())
        {
            if let Some(text) = choice.get("text").and_then(Value::as_str)
                && !text.is_empty()
            {
                events.push(GatewayEvent::TextDelta { text: text.into() });
            }
            if !choice
                .get("finish_reason")
                .unwrap_or(&Value::Null)
                .is_null()
            {
                events.extend(self.complete()?);
            }
        }
        Ok(events)
    }

    fn push_responses(&mut self, value: &Value) -> anyhow::Result<Vec<GatewayEvent>> {
        let event_type = value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let response = value.get("response").unwrap_or(value);
        let mut events = match event_type {
            "response.created" | "response.in_progress" => self.started_event(
                response
                    .get("id")
                    .or_else(|| value.get("response_id"))
                    .and_then(Value::as_str),
            ),
            _ => Vec::new(),
        };
        match event_type {
            "response.output_text.delta" => append_delta(&mut events, value, false),
            "response.reasoning_summary_text.delta" | "response.reasoning_text.delta" => {
                append_delta(&mut events, value, true);
            }
            "response.output_item.added" => self.capture_response_tool(value),
            "response.function_call_arguments.delta" => {
                let index = output_index(value);
                self.response_tools
                    .entry(index)
                    .or_default()
                    .arguments
                    .push_str(
                        value
                            .get("delta")
                            .and_then(Value::as_str)
                            .unwrap_or_default(),
                    );
            }
            "response.output_item.done" => {
                if let Some(event) = self.take_response_tool(value)? {
                    events.push(event);
                }
            }
            "response.completed" => {
                if let Some(usage) = response.get("usage") {
                    append_usage(&mut events, usage);
                }
                events.extend(self.complete()?);
            }
            "response.failed" | "response.incomplete" | "error" => {
                events.push(GatewayEvent::Error {
                    message: stream_error_message(value),
                });
                self.completed = true;
            }
            _ => {}
        }
        Ok(events)
    }

    fn capture_response_tool(&mut self, value: &Value) {
        let item = value.get("item").unwrap_or(&Value::Null);
        if item.get("type").and_then(Value::as_str) != Some("function_call") {
            return;
        }
        let call = self.response_tools.entry(output_index(value)).or_default();
        call.call_id = item
            .get("call_id")
            .or_else(|| item.get("id"))
            .and_then(Value::as_str)
            .map(str::to_string);
        call.name = item.get("name").and_then(Value::as_str).map(str::to_string);
        if let Some(arguments) = item.get("arguments").and_then(Value::as_str) {
            call.arguments.push_str(arguments);
        }
    }

    fn take_response_tool(&mut self, value: &Value) -> anyhow::Result<Option<GatewayEvent>> {
        let item = value.get("item").unwrap_or(&Value::Null);
        if item.get("type").and_then(Value::as_str) == Some("function_call") {
            let call = self.response_tools.entry(output_index(value)).or_default();
            call.call_id = item
                .get("call_id")
                .or_else(|| item.get("id"))
                .and_then(Value::as_str)
                .map(str::to_string)
                .or_else(|| call.call_id.clone());
            call.name = item
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_string)
                .or_else(|| call.name.clone());
            if let Some(arguments) = item.get("arguments").and_then(Value::as_str) {
                call.arguments = arguments.to_string();
            }
        }
        self.response_tools
            .remove(&output_index(value))
            .map(|call| response_tool_event(call, &self.tool_map))
            .transpose()
    }

    fn started_event(&mut self, response_id: Option<&str>) -> Vec<GatewayEvent> {
        if self.response_started {
            return Vec::new();
        }
        let Some(response_id) = response_id else {
            return Vec::new();
        };
        self.response_started = true;
        vec![GatewayEvent::ResponseStarted {
            response_id: response_id.to_string(),
        }]
    }

    fn complete(&mut self) -> anyhow::Result<Vec<GatewayEvent>> {
        if self.completed {
            return Ok(Vec::new());
        }
        let mut events = Vec::new();
        for call in self.chat_tools.finish_all()? {
            events.push(mapped_tool_event(
                call.call_id,
                call.name,
                call.arguments,
                &self.tool_map,
            )?);
        }
        let response_tools = std::mem::take(&mut self.response_tools);
        for (_, call) in response_tools {
            events.push(response_tool_event(call, &self.tool_map)?);
        }
        events.push(GatewayEvent::Completed);
        self.completed = true;
        Ok(events)
    }
}

fn response_tool_event(
    call: ResponseToolCall,
    tool_map: &ToolNameMap,
) -> anyhow::Result<GatewayEvent> {
    let call_id = call
        .call_id
        .ok_or_else(|| anyhow::anyhow!("streaming tool call missing call id"))?;
    let name = call
        .name
        .ok_or_else(|| anyhow::anyhow!("streaming tool call missing name"))?;
    let arguments = if call.arguments.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&call.arguments)?
    };
    mapped_tool_event(call_id, name, arguments, tool_map)
}

fn mapped_tool_event(
    call_id: String,
    wire_name: String,
    arguments: Value,
    tool_map: &ToolNameMap,
) -> anyhow::Result<GatewayEvent> {
    let canonical = tool_map
        .canonical_name(&wire_name)
        .ok_or_else(|| anyhow::anyhow!("unknown provider tool name"))?;
    Ok(GatewayEvent::ToolCall {
        call_id,
        name: canonical.to_string(),
        legacy_alias_selected: tool_map
            .advertised_name(&wire_name)
            .is_some_and(|advertised| advertised != canonical),
        arguments,
    })
}

fn append_delta(events: &mut Vec<GatewayEvent>, value: &Value, reasoning: bool) {
    let Some(text) = value.get("delta").and_then(Value::as_str) else {
        return;
    };
    if text.is_empty() {
        return;
    }
    events.push(if reasoning {
        GatewayEvent::ReasoningDelta { text: text.into() }
    } else {
        GatewayEvent::TextDelta { text: text.into() }
    });
}

fn append_usage(events: &mut Vec<GatewayEvent>, usage: &Value) {
    let input_tokens = usage
        .get("input_tokens")
        .or_else(|| usage.get("prompt_tokens"))
        .and_then(Value::as_u64);
    let output_tokens = usage
        .get("output_tokens")
        .or_else(|| usage.get("completion_tokens"))
        .and_then(Value::as_u64);
    if let (Some(input_tokens), Some(output_tokens)) = (input_tokens, output_tokens) {
        events.push(GatewayEvent::Usage {
            input_tokens,
            output_tokens,
        });
    }
}

fn output_index(value: &Value) -> usize {
    value
        .get("output_index")
        .or_else(|| value.get("item_index"))
        .and_then(Value::as_u64)
        .unwrap_or(0) as usize
}

fn stream_error_message(value: &Value) -> String {
    value
        .pointer("/error/message")
        .or_else(|| value.pointer("/response/error/message"))
        .or_else(|| value.get("message"))
        .and_then(Value::as_str)
        .unwrap_or("streaming model response failed")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        provider::ProviderProfile,
        responses::{GatewayHttpClient, GatewayRequest, GatewayTool},
    };
    use futures::StreamExt;
    use std::collections::BTreeMap;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[test]
    fn decoder_preserves_utf8_across_chunks_and_parses_multiple_frames() {
        let mut decoder = SseDecoder::default();
        let text = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"你好\"}\n\n";
        let split = text.find('好').unwrap() + 1;
        assert!(decoder.push(&text.as_bytes()[..split]).unwrap().is_empty());
        let frames = decoder.push(&text.as_bytes()[split..]).unwrap();
        assert_eq!(frames.len(), 1);
        assert!(frames[0].data.contains("你好"));
    }

    #[test]
    fn responses_stream_emits_deltas_usage_and_one_terminal_event() {
        let map = ToolNameMap::from_tools(&[]).unwrap();
        let mut parser = GatewayStreamParser::new(EndpointType::Responses, map);
        let frames = [
            frame(r#"{"type":"response.created","response":{"id":"resp-1"}}"#),
            frame(r#"{"type":"response.output_text.delta","delta":"hello"}"#),
            frame(
                r#"{"type":"response.completed","response":{"usage":{"input_tokens":2,"output_tokens":3}}}"#,
            ),
            frame("[DONE]"),
        ];
        let events = frames
            .into_iter()
            .flat_map(|frame| parser.push(frame).unwrap())
            .collect::<Vec<_>>();
        assert!(matches!(events[0], GatewayEvent::ResponseStarted { .. }));
        assert!(matches!(events[1], GatewayEvent::TextDelta { ref text } if text == "hello"));
        assert_eq!(
            events
                .iter()
                .filter(|event| matches!(event, GatewayEvent::Completed))
                .count(),
            1
        );
    }

    #[test]
    fn responses_done_item_replaces_argument_deltas_without_duplication() {
        let tool = GatewayTool::new(
            "package/tool",
            "tool",
            serde_json::json!({ "type": "object" }),
        );
        let map = ToolNameMap::from_tools(std::slice::from_ref(&tool)).unwrap();
        let wire = map.wire_name(&tool.id).unwrap();
        let mut parser = GatewayStreamParser::new(EndpointType::Responses, map.clone());
        parser
            .push(frame(&format!(
                r#"{{"type":"response.output_item.added","output_index":0,"item":{{"type":"function_call","call_id":"call-1","name":"{wire}","arguments":""}}}}"#
            )))
            .unwrap();
        parser
            .push(frame(
                r#"{"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\"path\":\"a.txt\"}"}"#,
            ))
            .unwrap();
        let events = parser
            .push(frame(&format!(
                r#"{{"type":"response.output_item.done","output_index":0,"item":{{"type":"function_call","call_id":"call-1","name":"{wire}","arguments":"{{\"path\":\"a.txt\"}}"}}}}"#
            )))
            .unwrap();
        assert!(matches!(
            &events[0],
            GatewayEvent::ToolCall { arguments, .. } if arguments["path"] == "a.txt"
        ));
    }

    #[test]
    fn truncated_stream_fails_instead_of_committing_partial_text() {
        let map = ToolNameMap::from_tools(&[]).unwrap();
        let mut parser = GatewayStreamParser::new(EndpointType::Responses, map);
        parser
            .push(frame(
                r#"{"type":"response.output_text.delta","delta":"partial"}"#,
            ))
            .unwrap();
        assert!(parser.finish().is_err());
    }

    #[test]
    fn chat_stream_assembles_tool_arguments_with_canonical_identity() {
        let tool = GatewayTool::new(
            "package/tool",
            "tool",
            serde_json::json!({ "type": "object" }),
        );
        let map = ToolNameMap::from_tools(std::slice::from_ref(&tool)).unwrap();
        let wire = map.wire_name(&tool.id).unwrap().to_string();
        let mut parser = GatewayStreamParser::new(EndpointType::ChatCompletions, map);
        let first = frame(&format!(
            r#"{{"id":"resp-1","choices":[{{"delta":{{"tool_calls":[{{"index":0,"id":"call-1","function":{{"name":"{wire}","arguments":"{{\"path\""}}}}]}}}}]}}"#
        ));
        let second = frame(
            r#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\"a.txt\"}"}}]},"finish_reason":"tool_calls"}]}"#,
        );
        parser.push(first).unwrap();
        let events = parser.push(second).unwrap();
        assert!(matches!(
            &events[0],
            GatewayEvent::ToolCall { name, arguments, .. }
                if name == "package/tool" && arguments["path"] == "a.txt"
        ));
    }

    #[tokio::test]
    async fn http_client_delivers_sse_delta_before_terminal_frame() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut request = vec![0u8; 16 * 1024];
            let _ = socket.read(&mut request).await.unwrap();
            socket
                .write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n",
                )
                .await
                .unwrap();
            socket
                .write_all(
                    b"data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-1\"}}\n\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"first\"}\n\n",
                )
                .await
                .unwrap();
            socket.flush().await.unwrap();
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            socket
                .write_all(
                    b"data: {\"type\":\"response.completed\",\"response\":{}}\n\ndata: [DONE]\n\n",
                )
                .await
                .unwrap();
        });
        let client = GatewayHttpClient::new(ProviderProfile {
            id: "stream-test".into(),
            name: "Stream test".into(),
            endpoint_type: EndpointType::Responses,
            base_url: format!("http://{address}/v1"),
            model: "test".into(),
            api_key: None,
            headers: BTreeMap::new(),
        });
        let mut stream = client
            .stream(GatewayRequest {
                input: vec![serde_json::json!({ "role": "user", "content": "hello" })],
                tools: Vec::new(),
            })
            .await
            .unwrap();
        assert!(matches!(
            stream.next().await.unwrap().unwrap(),
            GatewayEvent::ResponseStarted { .. }
        ));
        assert!(matches!(
            stream.next().await.unwrap().unwrap(),
            GatewayEvent::TextDelta { ref text } if text == "first"
        ));
        assert!(matches!(
            stream.next().await.unwrap().unwrap(),
            GatewayEvent::Completed
        ));
        server.await.unwrap();
    }

    fn frame(data: &str) -> SseFrame {
        SseFrame {
            event: None,
            data: data.to_string(),
        }
    }
}
