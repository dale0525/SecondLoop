import 'dart:convert';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

String buildLocalQaWorkerScript() {
  final checks = [
    ModelCapabilityRequiredChecks.structuredOutput,
    ModelCapabilityRequiredChecks.secretaryMetadata,
    ModelCapabilityRequiredChecks.toolProposalDiscipline,
    ModelCapabilityRequiredChecks.multimodalUnderstanding,
    ModelCapabilityRequiredChecks.chineseIntentHandling,
    ModelCapabilityRequiredChecks.contextWindowLatency,
    ModelCapabilityRequiredChecks.clarificationBehavior,
    ModelCapabilityRequiredChecks.sideEffectDiscipline,
  ];
  final capabilities = [
    ...CloudRuntimeRequiredCapabilities.all.map((capability) => capability.id),
    'deployment_test_api',
    'runtime_test_api',
  ];
  return '''
const checks = ${jsonEncode(checks)};
const capabilities = ${jsonEncode(capabilities)};
const memoryStates = new Map();
const statePrefix = "secondloop:local-qa-runtime:v2:";
const blobPrefix = "secondloop:local-qa-blob:v1:";
function json(body, init = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...(init.headers || {})
    }
  });
}
function nowMs() {
  return Date.now();
}
function cleanText(value) {
  return String(value || "").trim();
}
function trimTrailingPunctuation(value) {
  let text = cleanText(value);
  while (text.endsWith("。") || text.endsWith(".") || text.endsWith("！") ||
      text.endsWith("!") || text.endsWith("？") || text.endsWith("?")) {
    text = text.slice(0, -1).trim();
  }
  return text;
}
function normalizeVaultId(value) {
  const decoded = decodeURIComponent(cleanText(value || "local-vault"));
  return decoded || "local-vault";
}
function defaultState(vaultId) {
  return {
    vault_id: vaultId, conversations: {}, conversation_turns: [],
    tasks: [], memory_records: [], recurring_reminder_rules: [],
    approval_items: [], recent_entity_refs: [], audit_refs: [],
    working_set_records: [], runs: {}, next_conversation_seq: 1,
    next_turn_seq: 1, next_task_seq: 1, next_memory_seq: 1,
    next_approval_seq: 1, next_run_seq: 1
  };
}
function normalizeState(raw, vaultId) {
  const state = raw && typeof raw === "object" ? raw : defaultState(vaultId);
  const base = defaultState(vaultId);
  return {
    ...base,
    ...state,
    vault_id: vaultId,
    conversations: state.conversations && typeof state.conversations === "object" ? state.conversations : {},
    conversation_turns: Array.isArray(state.conversation_turns) ? state.conversation_turns : [],
    tasks: Array.isArray(state.tasks) ? state.tasks : [],
    memory_records: Array.isArray(state.memory_records) ? state.memory_records : [],
    recurring_reminder_rules: Array.isArray(state.recurring_reminder_rules) ? state.recurring_reminder_rules : [],
    approval_items: Array.isArray(state.approval_items) ? state.approval_items : [],
    recent_entity_refs: Array.isArray(state.recent_entity_refs) ? state.recent_entity_refs : [],
    audit_refs: Array.isArray(state.audit_refs) ? state.audit_refs : [],
    working_set_records: Array.isArray(state.working_set_records) ? state.working_set_records : [],
    runs: state.runs && typeof state.runs === "object" ? state.runs : {},
    next_conversation_seq: Number(state.next_conversation_seq || 1),
    next_turn_seq: Number(state.next_turn_seq || 1),
    next_task_seq: Number(state.next_task_seq || 1),
    next_memory_seq: Number(state.next_memory_seq || 1),
    next_approval_seq: Number(state.next_approval_seq || 1),
    next_run_seq: Number(state.next_run_seq || 1)
  };
}
async function readState(env, vaultId) {
  const normalizedVaultId = normalizeVaultId(vaultId);
  const key = statePrefix + normalizedVaultId;
  if (env.KV && typeof env.KV.get === "function") {
    const stored = await env.KV.get(key, { type: "json" });
    return normalizeState(stored, normalizedVaultId);
  }
  return normalizeState(memoryStates.get(key), normalizedVaultId);
}
async function writeState(env, state) {
  const key = statePrefix + state.vault_id;
  if (env.KV && typeof env.KV.put === "function") {
    await env.KV.put(key, JSON.stringify(state));
  }
  memoryStates.set(key, state);
}
async function requestJson(request) {
  try {
    const decoded = await request.json();
    return decoded && typeof decoded === "object" ? decoded : {};
  } catch (_) {
    return {};
  }
}
function ensureConversation(state, conversationId) {
  const id = cleanText(conversationId) ||
    "conversation-" + state.next_conversation_seq++;
  if (!state.conversations[id]) {
    state.conversations[id] = {
      conversation_id: id,
      created_at_ms: nowMs(),
      updated_at_ms: nowMs()
    };
  } else {
    state.conversations[id].updated_at_ms = nowMs();
  }
  return id;
}
function appendTurn(state, conversationId, role, content, extra = {}) {
  const createdAtMs = nowMs();
  const turn = {
    turn_id: "turn-" + state.next_turn_seq++,
    conversation_id: conversationId,
    vault_id: state.vault_id,
    role,
    content: cleanText(content),
    attachment_refs: [],
    created_at_ms: createdAtMs,
    ...extra
  };
  state.conversation_turns.push(turn);
  return turn;
}
function workingSetRecord(record) {
  return {
    id: cleanText(record.id),
    kind: cleanText(record.kind),
    title: cleanText(record.title),
    text: cleanText(record.text || record.title),
    summary: cleanText(record.summary || record.title),
    body: cleanText(record.body || record.text || record.title),
    status: cleanText(record.status || "open"),
    updated_at_ms: Number(record.updated_at_ms || record.created_at_ms || nowMs()),
    ...record
  };
}
function extractAfterAny(text, markers) {
  for (const marker of markers) {
    const index = text.indexOf(marker);
    if (index >= 0) {
      return trimTrailingPunctuation(text.slice(index + marker.length));
    }
  }
  return "";
}
function taskTitleFromMessage(message) {
  const text = cleanText(message);
  if (!(text.includes("创建") || text.includes("新增"))) return "";
  if (!(text.includes("任务") || text.includes("待办"))) return "";
  const title = extractAfterAny(text, [
    "任务：",
    "任务:",
    "新任务：",
    "新任务:",
    "待办事项：",
    "待办事项:",
    "待办：",
    "待办:"
  ]);
  return title || "新任务";
}
function memoryTextsFromMessage(message) {
  const text = cleanText(message);
  if (!text.includes("记住")) return [];
  return text
    .split("记住")
    .map((part) => trimTrailingPunctuation(part.replace(/^[:：]/, "")))
    .filter((part) => part.length > 0);
}
function isChildBirthdayReminderRequest(message) {
  return message.includes("每年") &&
    message.includes("孩子生日") &&
    message.includes("前一天") &&
    message.includes("提醒") &&
    message.includes("买礼物");
}
function hasChildBirthdayMemory(state) {
  return state.memory_records.some((memory) => {
    const haystack = [
      memory.title,
      memory.text,
      memory.summary,
      memory.body
    ].map(cleanText).join(" ");
    return haystack.includes("孩子生日");
  });
}
function isChildBirthdayAnswer(message) {
  return message.includes("孩子生日") &&
    (message.includes("6 月 1 日") || message.includes("6月1日"));
}
function childBirthdayMemoryText(message) {
  const match = message.match(/孩子生日是\\s*([0-9]{4}\\s*年\\s*[0-9]{1,2}\\s*月\\s*[0-9]{1,2}\\s*日)/);
  const date = match ? match[1].replace(/\\s+/g, " ") : "2018 年 6 月 1 日";
  return "孩子生日是 " + date;
}
function createTask(state, title, sourceTurnId) {
  const createdAtMs = nowMs();
  const task = workingSetRecord({
    id: "task-" + state.next_task_seq++, kind: "task", title, text: title,
    summary: title, body: title, status: "open",
    source_message_id: sourceTurnId, source_entry_id: sourceTurnId,
    created_at_ms: createdAtMs, updated_at_ms: createdAtMs
  });
  state.tasks.push(task);
  return task;
}
function createApproval(state, kind, title, sourceTurnId, record = {}) {
  const createdAtMs = nowMs();
  const approval = {
    id: "approval-" + state.next_approval_seq++, kind, title,
    task_id: cleanText(record.task_id),
    recurring_rule_id: cleanText(record.recurring_rule_id || record.id),
    reason: cleanText(record.reason || title),
    editable_fields: Array.isArray(record.editable_fields) ? record.editable_fields : [],
    version: Number(record.version || 1), source_intent_id: sourceTurnId,
    created_at_ms: createdAtMs,
    record: {
      ...record, title, source_message_id: sourceTurnId,
      created_at_ms: createdAtMs, updated_at_ms: createdAtMs
    }
  };
  state.approval_items.push(approval);
  return approval;
}
function buildMetadata(state, runId, conversationId, assistantTurn, overrides = {}) {
  return {
    run_id: runId, turn_id: assistantTurn.turn_id,
    conversation_id: conversationId, vault_id: state.vault_id,
    response_type: "assistant_message", run_status: "completed",
    approval_required: false, confidence: 0.92, referenced_entities: {},
    proposed_mutations: [], applied_mutations: [], draft_entities: [],
    approval_items: [], media_results: [], web_research_drafts: [],
    tool_trace_ids: ["local-qa-runtime"],
    provider_trace_id: "local-qa-provider",
    requires_high_cost_confirmation: false,
    ...overrides
  };
}
function makeRunResult(state, conversationId, assistantTurn, metadataOverrides = {}) {
  const runId = "run-" + state.next_run_seq++;
  const metadata = buildMetadata(state, runId, conversationId, assistantTurn, metadataOverrides);
  const result = { run_id: runId, conversation_id: conversationId, assistant: { role: "assistant", content: assistantTurn.content }, metadata };
  state.runs[runId] = result;
  return result;
}
function webResearchPayload(assistantContent) {
  const citations = [
    {
      href: "https://www.apple.com/newsroom/",
      title: "Apple Newsroom",
      domain: "apple.com",
      snippet: "用于本地 QA 的 self-managed runtime citation。"
    },
    {
      href: "https://www.apple.com/iphone/",
      title: "iPhone",
      domain: "apple.com",
      snippet: "用于连续对话参数说明的来源占位。"
    }
  ];
  return {
    query: "Apple 发布会 新产品",
    summary: assistantContent,
    citations,
    fetched_at_ms: nowMs()
  };
}
function mediaResultForAttachment(attachment, sourceTurnId) {
  const filename = cleanText(
    attachment.filename || attachment.display_name || attachment.name || "attachment"
  );
  const attachmentId = cleanText(
    attachment.attachment_id || attachment.id || attachment.sha256 || attachment.blob_id
  );
  const base = {
    id: "media-" + (attachmentId || filename) + "-" + cleanText(sourceTurnId),
    kind: "media_result",
    source_message_id: sourceTurnId,
    attachment_id: attachmentId,
    source_id: attachmentId,
    filename,
    media_type: cleanText(attachment.media_type || attachment.type || "file"),
    saved_to_vault: true,
    citations: [{ title: filename }]
  };
  if (filename.includes("qa-ocr")) {
    return {
      ...base,
      media_type: "image",
      ocr_text: "QA MEDIA",
      summary: "图片中包含 QA MEDIA 字样。",
      confidence_percent: 98
    };
  }
  if (filename.includes("qa-scan")) {
    const text = "PASSPORT EXPIRES 2030-06-01\\nQA scan sample for manual media pipeline acceptance.";
    return {
      ...base,
      media_type: "document",
      ocr_text: text,
      readable_text_full: text,
      summary: "PDF 关键信息：证件到期日为 2030-06-01；这是 manual media pipeline acceptance 的 QA 扫描样本。",
      confidence_percent: 96
    };
  }
  if (filename.includes("qa-meeting-audio")) {
    return {
      ...base,
      media_type: "audio",
      filename: "Meeting Summary",
      meeting_id: "MTG-QA-AUDIO-001",
      duration_label: "0:07",
      transcript: "Maya 提醒团队确认发布 checklist。Jordan 同意今天整理风险，Priya 负责预算确认。",
      meeting_summary: "会议纪要：团队确认发布 checklist、风险整理和预算确认三项后续工作。",
      decisions: ["采用发布 checklist 跟踪 QA 收尾。", "预算确认完成前不扩大发布范围。"],
      action_items: [
        { title: "整理发布 checklist", owner: "Maya", due: "today" },
        { title: "汇总 QA 风险", owner: "Jordan" },
        { title: "确认预算要求", owner: "Priya" }
      ],
      high_fidelity_confirmed: true,
      confidence_percent: 94
    };
  }
  return { ...base, summary: "已收到附件，等待真实媒体 provider 处理。", saved_to_vault: false };
}
function addWorkingSetRecords(state, records) {
  for (const record of records) state.working_set_records.push(workingSetRecord(record));
}
function latestQaImageMediaResult(state) {
  for (const turn of [...state.conversation_turns].reverse()) {
    const results = Array.isArray(turn.media_results) ? turn.media_results : [];
    const found = results.find((result) => cleanText(result.ocr_text) === "QA MEDIA");
    if (found) return found;
  }
  return null;
}
function mediaResponseContent(mediaResults) {
  if (mediaResults.some((result) => result.media_type === "audio")) {
    return "我已完成会议音频转写，整理了会议纪要、决策和行动项。";
  }
  if (mediaResults.some((result) => result.filename.includes("qa-scan"))) {
    return "我提取了 PDF 关键字段：PASSPORT EXPIRES 2030-06-01，并附上来源。";
  }
  if (mediaResults.some((result) => cleanText(result.ocr_text) === "QA MEDIA")) {
    return "我识别到图片中的关键文字：QA MEDIA，并生成了摘要。";
  }
  return "我已收到附件；当前本地 QA runtime 会记录附件来源，真实解析依赖 self-managed 媒体 provider。";
}
function createAudioActionApprovals(state, conversationId, sourceTurnId) {
  const items = [
    ["ACT-QA-001", "整理发布 checklist", "Maya", "today"],
    ["ACT-QA-002", "汇总 QA 风险", "Jordan", ""],
    ["ACT-QA-003", "确认预算要求", "Priya", ""]
  ];
  return items.map((item) => createApproval(state, "action_item_candidate", item[1], sourceTurnId, {
    kind: "action_item_candidate",
    candidate_id: item[0],
    owner: item[2],
    due_label: item[3],
    risk: "Low",
    source_id: "MTG-QA-AUDIO-001",
    reason: "Create an action item from the QA meeting audio transcript.",
    conversation_id: conversationId
  }));
}
function taskMutationRequested(message) {
  return (
    message.includes("任务") ||
    message.includes("待办")
  ) && (
    message.includes("改为") ||
    message.includes("改成") ||
    message.includes("改到") ||
    message.includes("调整到")
  );
}
function ambiguousTaskTargetFromMessage(message) {
  if (!taskMutationRequested(message)) return "";
  if (message.toLowerCase().includes("alex")) return "Alex";
  return "";
}
function tasksMatchingTarget(state, target) {
  const normalizedTarget = cleanText(target).toLowerCase();
  if (!normalizedTarget) return [];
  return state.tasks.filter((task) => {
    const haystack = [
      task.title,
      task.text,
      task.summary,
      task.body
    ].map(cleanText).join(" ").toLowerCase();
    return haystack.includes(normalizedTarget);
  });
}
function answerForMessage(state, conversationId, userTurn, body) {
  const message = cleanText(body.message_display_text || body.message);
  const attachments = Array.isArray(body.attachments) ? body.attachments : [];
  const taskTitle = taskTitleFromMessage(message);
  if (taskTitle) {
    const task = createTask(state, taskTitle, userTurn.turn_id);
    const assistantTurn = appendTurn(
      state,
      conversationId,
      "assistant",
      "已创建任务：" + task.title + "。"
    );
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "task_created",
      referenced_entities: { tasks: [task.id] },
      applied_mutations: [
        {
          entity_type: "task",
          entity_id: task.id,
          mutation_type: "create",
          status: "applied"
        }
      ],
      state_snapshot_after: { tasks: [task.id] }
    });
  }
  const memoryTexts = memoryTextsFromMessage(message);
  if (memoryTexts.length > 0) {
    const approvals = memoryTexts.map((text) =>
      createApproval(state, "memory_confirmation", text, userTurn.turn_id, {
        memory_kind: "preference",
        body: text,
        state: "candidate",
        conversation_id: conversationId
      })
    );
    const assistantTurn = appendTurn(
      state,
      conversationId,
      "assistant",
      "我提取了 " + approvals.length + " 条记忆候选，等待你确认。"
    );
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "memory_candidates_pending",
      run_status: "waiting_for_approval",
      approval_required: true,
      approval_items: approvals,
      proposed_mutations: approvals.map((approval) => ({
        entity_type: "memory",
        entity_id: approval.id,
        mutation_type: "create",
        status: "pending_approval"
      }))
    });
  }
  if (message.includes("最早") && message.includes("项目代号") && message.includes("默认汇报对象")) {
    const assistantTurn = appendTurn(state, conversationId, "assistant", "最早告诉我的项目代号是长河计划，默认汇报对象是 Mira。");
    return makeRunResult(state, conversationId, assistantTurn, { response_type: "long_context_recall" });
  }
  if (isChildBirthdayReminderRequest(message) && !hasChildBirthdayMemory(state)) {
    const assistantTurn = appendTurn(
      state,
      conversationId,
      "assistant",
      "我需要先知道孩子生日，才能计算每年提前一天提醒买礼物。请告诉我孩子生日。"
    );
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "clarification_required",
      run_status: "needs_clarification",
      draft_entities: [
        {
          entity_type: "recurring_reminder_rule",
          title: "给孩子买生日礼物",
          status: "missing_required_slot",
          missing_slot: "child birthday"
        }
      ]
    });
  }
  if (isChildBirthdayAnswer(message)) {
    const memoryText = childBirthdayMemoryText(message);
    const memoryApproval = createApproval(
      state,
      "memory_confirmation",
      memoryText,
      userTurn.turn_id,
      {
        memory_kind: "profile_fact",
        body: memoryText,
        text: memoryText,
        state: "candidate",
        conflict_risk: "Low",
        audit_id: "local-qa-memory-child-birthday",
        conversation_id: conversationId
      }
    );
    const reminderApproval = createApproval(
      state,
      "recurring_reminder_confirmation",
      "给孩子买生日礼物",
      userTurn.turn_id,
      {
        id: "recurring-rule-child-birthday-gift",
        recurring_rule_id: "recurring-rule-child-birthday-gift",
        kind: "recurring_reminder_rule",
        title: "给孩子买生日礼物",
        text: "给孩子买生日礼物",
        schedule_label: "Every year on May 31",
        next_trigger_label: "2026 年 5 月 31 日",
        next_trigger_at: "2026-05-31T09:00:00+08:00",
        rrule: "FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=31",
        risk_assessment: "Low",
        audit_id: "local-qa-reminder-child-birthday-gift",
        editable_fields: ["title"],
        approval_status: "pending_approval",
        conversation_id: conversationId
      }
    );
    const approvals = [memoryApproval, reminderApproval];
    const assistantTurn = appendTurn(
      state,
      conversationId,
      "assistant",
      "我提取了孩子生日记忆，并生成了每年 5 月 31 日买礼物的循环提醒候选，等待你确认。"
    );
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "recurring_reminder_candidate",
      run_status: "waiting_for_approval",
      approval_required: true,
      approval_items: approvals,
      proposed_mutations: [
        {
          entity_type: "memory",
          entity_id: memoryApproval.id,
          mutation_type: "create",
          status: "pending_approval"
        },
        {
          entity_type: "recurring_reminder_rule",
          entity_id: reminderApproval.recurring_rule_id,
          mutation_type: "create",
          status: "pending_approval"
        }
      ]
    });
  }
  const ambiguousTaskTarget = ambiguousTaskTargetFromMessage(message);
  if (ambiguousTaskTarget) {
    const matches = tasksMatchingTarget(state, ambiguousTaskTarget);
    if (matches.length > 1) {
      const options = matches
        .map((task, index) => (index + 1) + ". " + task.title)
        .join("；");
      const assistantTurn = appendTurn(
        state,
        conversationId,
        "assistant",
        "我找到 " + matches.length + " 个 Alex 相关任务：" + options +
          "。请确认要修改哪一个后，我再生成审批。"
      );
      return makeRunResult(state, conversationId, assistantTurn, {
        response_type: "clarification_required",
        run_status: "needs_clarification",
        referenced_entities: { tasks: matches.map((task) => task.id) },
        draft_entities: matches.map((task) => ({
          entity_type: "task",
          entity_id: task.id,
          title: task.title,
          status: "clarification_option"
        })),
        state_snapshot_after: { tasks: matches.map((task) => task.id) }
      });
    }
  }
  if (message.includes("改为") && (message.includes("任务") || message.includes("待办"))) {
    const latestTask = state.tasks[state.tasks.length - 1];
    const nextTitle = extractAfterAny(message, ["改为", "改成"]) || "更新后的任务";
    const approval = createApproval(
      state,
      "task_mutation_confirmation",
      nextTitle,
      userTurn.turn_id,
      {
        task_id: latestTask ? latestTask.id : "",
        mutation_type: "rename",
        body: nextTitle,
        conversation_id: conversationId
      }
    );
    const assistantTurn = appendTurn(
      state,
      conversationId,
      "assistant",
      "待确认：将任务标题改为 " + nextTitle + "。"
    );
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "formal_mutation_pending",
      run_status: "waiting_for_approval",
      approval_required: true,
      approval_items: [approval],
      referenced_entities: { tasks: latestTask ? [latestTask.id] : [] },
      proposed_mutations: [
        {
          entity_type: "task",
          entity_id: latestTask ? latestTask.id : "",
          mutation_type: "rename",
          status: "pending_approval"
        }
      ]
    });
  }
  const applePhoneFollowup =
    (message.includes("手机") || message.toLowerCase().includes("iphone")) &&
    (message.includes("参数") || message.includes("产品"));
  if (message.includes("查一下") || message.toLowerCase().includes("research") ||
      applePhoneFollowup) {
    const content = applePhoneFollowup
      ? "承接上一轮 Apple 发布会结果，新手机产品参数重点包括 iPhone 系列、芯片、影像、续航和生态功能；下面继续带上来源。"
      : "我查到 Apple 近期发布会重点包括新款 iPhone、芯片和生态功能。下面带上来源，后续问题会沿用这轮上下文。";
    const draft = webResearchPayload(content);
    const assistantTurn = appendTurn(state, conversationId, "assistant", content, {
      web_research_drafts: [draft]
    });
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "web_research_answer",
      web_research_drafts: [draft]
    });
  }
  if (message.includes("前面") && message.includes("图片") &&
      (message.includes("关键文字") || message.includes("识别"))) {
    const previous = latestQaImageMediaResult(state);
    const attachmentId = previous ? cleanText(previous.attachment_id || previous.source_id) : "";
    const content = previous
      ? "我记得前面那张图片识别出的关键文字是 QA MEDIA；依据的是附件 " + attachmentId + "。"
      : "我没有找到可用的旧图片 OCR 结果。";
    const assistantTurn = appendTurn(state, conversationId, "assistant", content);
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: previous ? "attachment_recall" : "attachment_recall_unavailable",
      referenced_entities: previous ? { attachments: [attachmentId] } : {}
    });
  }
  if (message.includes("周报邮件") && message.includes("Alice") && !message.includes("内容说")) { addWorkingSetRecords(state, [{ id: "email-draft-weekly-alice-" + userTurn.turn_id, kind: "email_draft_only", title: "周报邮件草稿", recipients: ["Alice"], subject: "周报", body: "这里是周报草稿。", source: "self-managed runtime", source_message_id: userTurn.turn_id, audit_id: "local-qa-email-draft" }, { id: "email-block-" + userTurn.turn_id, kind: "email_authorization_block", title: "Email send blocked", tool: "email.send", action: "email.send", blocked_action: "email.send", connector: "Email (Disconnected)", status: "tool_unavailable", status_label: "Not Executed (Email not connected)", reason: "Email connector is not authorized.", source_message_id: userTurn.turn_id, audit_id: "local-qa-email-block" }]); const assistantTurn = appendTurn(state, conversationId, "assistant", "我没有发送邮件。当前邮箱未连接，只能生成草稿；请先连接邮箱，发送仍需要你审批。"); return makeRunResult(state, conversationId, assistantTurn, { response_type: "email_draft_only", draft_entities: [{ entity_type: "email_draft", recipient: "Alice", status: "draft_only" }] }); }
  if (message.includes("周报邮件") && message.includes("Alice") && message.includes("内容说")) { const approval = createApproval(state, "email_send_confirmation", "发送周报邮件给 Alice", userTurn.turn_id, { kind: "email_send_confirmation", email_draft_id: "email-draft-weekly-alice", recipients: ["Alice"], subject: "周报", body: "本周进展顺利。", tool: "email.send", audit_id: "local-qa-email-send", conversation_id: conversationId }); approval.email_draft_id = "email-draft-weekly-alice"; addWorkingSetRecords(state, [{ id: "email-draft-weekly-alice", kind: "email_draft_candidate", title: "周报邮件草稿", recipients: ["Alice"], subject: "周报", body: "本周进展顺利。", source: "self-managed runtime", source_message_id: userTurn.turn_id, audit_id: "local-qa-email-send" }]); const assistantTurn = appendTurn(state, conversationId, "assistant", "已起草周报邮件；发送前需要审批，未审批不会产生外部副作用。"); return makeRunResult(state, conversationId, assistantTurn, { response_type: "email_send_confirmation", run_status: "waiting_for_approval", approval_required: true, approval_items: [approval], proposed_mutations: [{ entity_type: "email", entity_id: approval.email_draft_id, mutation_type: "send", status: "pending_approval" }] }); }
  if (message.includes("明天下午 3 点") && message.includes("Alex") && message.includes("设计评审")) { const approval = createApproval(state, "calendar_event_confirmation", "Alex 设计评审", userTurn.turn_id, { kind: "calendar_event_confirmation", calendar_event_id: "cal-qa-design-review", title: "Alex 设计评审", time_label: "明天下午 3:00 - 3:30", participants: ["Alex"], tool_label: "calendar_tool", audit_id: "local-qa-calendar-create", source_message: message, conversation_id: conversationId }); approval.calendar_event_id = "cal-qa-design-review"; const assistantTurn = appendTurn(state, conversationId, "assistant", "已准备日历事件候选；创建日历前需要审批，拒绝不会产生外部副作用。"); return makeRunResult(state, conversationId, assistantTurn, { response_type: "calendar_event_confirmation", run_status: "waiting_for_approval", approval_required: true, approval_items: [approval], proposed_mutations: [{ entity_type: "calendar_event", entity_id: "cal-qa-design-review", mutation_type: "create", status: "pending_approval" }] }); }
  if (message.includes("生成今天的简报")) { const taskTitles = state.tasks.filter((task) => cleanText(task.status || "open") !== "done").slice(-4).map((task) => task.title).join("、") || "暂无未完成任务"; const assistantTurn = appendTurn(state, conversationId, "assistant", "今天的简报：未完成承诺包括 " + taskTitles + "。近期风险：邮箱/日历等 connector 未授权时不会编造外部摘要。下一步：优先处理明天截止事项并逐项确认风险。"); return makeRunResult(state, conversationId, assistantTurn, { response_type: "daily_brief" }); }
  if (message.includes("高铁票") || message.includes("付款")) { addWorkingSetRecords(state, [{ id: "safety-purchase-" + userTurn.turn_id, kind: "external_side_effect_blocked", title: "Purchase/payment refused", skill: "purchase-payment-safety", tool: "purchase-payment-safety", blocked_action: "ticket purchase + payment", status: "external_side_effect_blocked", status_label: "Refused / No external action", source_message_id: userTurn.turn_id, audit_id: "local-qa-purchase-payment-block" }]); const assistantTurn = appendTurn(state, conversationId, "assistant", "我不能替你直接购票或付款，也没有发起任何交易。我可以帮你整理查询条件、购票清单或提醒。"); return makeRunResult(state, conversationId, assistantTurn, { response_type: "external_side_effect_blocked" }); }
  if (message.includes("rm -rf") || message.includes("终端")) { addWorkingSetRecords(state, [{ id: "safety-local-" + userTurn.turn_id, kind: "tool_blocked", title: "Local computer operation refused", skill: "local-computer-safety", tool: "local-computer-safety", blocked_action: "terminal shell rm -rf local file", status: "blocked", status_label: "No command executed", source_message_id: userTurn.turn_id, audit_id: "local-qa-local-shell-block" }]); const assistantTurn = appendTurn(state, conversationId, "assistant", "我不能打开终端或执行会删除本机文件的命令；没有执行任何本机操作。我可以改为提供手动清理 checklist。"); return makeRunResult(state, conversationId, assistantTurn, { response_type: "local_computer_operation_refused" }); }
  if (attachments.length > 0) {
    const mediaResults = attachments.map((attachment) =>
      mediaResultForAttachment(attachment, userTurn.turn_id)
    );
    addWorkingSetRecords(state, mediaResults);
    const audioApprovals = mediaResults.some((result) => result.media_type === "audio")
      ? createAudioActionApprovals(state, conversationId, userTurn.turn_id)
      : [];
    const content = mediaResponseContent(mediaResults);
    const assistantTurn = appendTurn(state, conversationId, "assistant", content, {
      media_results: mediaResults
    });
    return makeRunResult(state, conversationId, assistantTurn, {
      response_type: "media_summary",
      media_results: mediaResults,
      approval_required: audioApprovals.length > 0,
      approval_items: audioApprovals,
      proposed_mutations: audioApprovals.map((approval) => ({
        entity_type: "task",
        entity_id: approval.id,
        mutation_type: "create",
        status: "pending_approval"
      }))
    });
  }
  const assistantTurn = appendTurn(state, conversationId, "assistant", "已收到，我会在 self-managed runtime 中继续跟进。"); return makeRunResult(state, conversationId, assistantTurn);
}
function pageTurns(state, conversationId, url) {
  const requestedConversationId = cleanText(conversationId);
  const allTurns = state.conversation_turns
    .filter((turn) => !requestedConversationId ||
      turn.conversation_id === requestedConversationId)
    .sort((a, b) => Number(a.created_at_ms || 0) - Number(b.created_at_ms || 0));
  const before = cleanText(url.searchParams.get("turn_before"));
  let endIndex = allTurns.length;
  if (before) {
    const found = allTurns.findIndex((turn) => turn.turn_id === before);
    if (found >= 0) endIndex = found;
  }
  const limit = Math.max(0, Number(url.searchParams.get("turn_limit") || 200));
  const startIndex = limit > 0 ? Math.max(0, endIndex - limit) : 0;
  const page = allTurns.slice(startIndex, endIndex);
  return {
    turns: page,
    page: {
      limit,
      has_more_before: startIndex > 0,
      next_before_turn_id: startIndex > 0 && page.length > 0 ? page[0].turn_id : "",
      oldest_turn_id: page.length > 0 ? page[0].turn_id : "",
      newest_turn_id: page.length > 0 ? page[page.length - 1].turn_id : "",
      total_known_turns: allTurns.length
    }
  };
}
function agentStateResponse(state, conversationId, url) {
  const page = pageTurns(state, conversationId, url);
  const workingSetRecords = [
    ...state.working_set_records,
    ...state.tasks,
    ...state.memory_records
  ].map(workingSetRecord);
  return {
    vault_id: state.vault_id,
    conversation_id: cleanText(conversationId),
    conversation_turns: page.turns,
    working_set_records: workingSetRecords,
    tasks: state.tasks.map(workingSetRecord),
    memory_records: state.memory_records.map(workingSetRecord),
    recurring_reminder_rules: state.recurring_reminder_rules,
    approval_items: state.approval_items,
    recent_entity_refs: state.recent_entity_refs,
    conversation_turn_page: page.page,
    latest_context_snapshot: {
      id: "context-" + state.vault_id,
      generated_at_ms: nowMs(),
      packet: {
        working_set: workingSetRecords,
        memory_records: state.memory_records,
        recurring_reminder_rules: state.recurring_reminder_rules
      }
    },
    audit_refs: state.audit_refs
  };
}
function applyApproval(state, approval, decision) {
  if (decision !== "approve") return null;
  const record = approval.record || {};
  if (approval.kind === "memory_confirmation") {
    const createdAtMs = nowMs();
    const memory = workingSetRecord({
      id: "memory-" + state.next_memory_seq++,
      kind: "memory",
      title: approval.title,
      text: approval.title,
      summary: approval.title,
      body: cleanText(record.body || approval.title),
      status: "active",
      state: "active",
      memory_kind: cleanText(record.memory_kind || "preference"),
      source_message_id: cleanText(record.source_message_id),
      created_at_ms: createdAtMs,
      updated_at_ms: createdAtMs
    });
    state.memory_records.push(memory);
    return { entity_type: "memory", entity_id: memory.id, mutation_type: "create" };
  }
  if (approval.kind === "task_mutation_confirmation") {
    const task = state.tasks.find((item) => item.id === approval.task_id);
    if (task) {
      task.title = approval.title;
      task.text = approval.title;
      task.summary = approval.title;
      task.body = approval.title;
      task.updated_at_ms = nowMs();
      return { entity_type: "task", entity_id: task.id, mutation_type: "rename" };
    }
  }
  if (approval.kind === "recurring_reminder_confirmation") {
    const createdAtMs = nowMs();
    const ruleId = cleanText(
      record.id || approval.recurring_rule_id || "recurring-rule-" + approval.id
    );
    const rule = {
      ...record,
      id: ruleId,
      kind: "recurring_reminder_rule",
      title: approval.title,
      text: approval.title,
      summary: approval.title,
      status: "active",
      approval_status: "approved",
      source_approval_id: approval.id,
      source_message_id: cleanText(record.source_message_id),
      created_at_ms: Number(record.created_at_ms || createdAtMs),
      updated_at_ms: createdAtMs
    };
    state.recurring_reminder_rules.push(rule);
    return {
      entity_type: "recurring_reminder_rule",
      entity_id: rule.id,
      mutation_type: "create"
    };
  }
  if (approval.kind === "action_item_candidate") {
    const task = createTask(state, approval.title, cleanText(record.source_message_id));
    task.owner = cleanText(record.owner);
    task.due_label = cleanText(record.due_label);
    return { entity_type: "task", entity_id: task.id, mutation_type: "create" };
  }
  return null;
}
function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}
function base64ToBytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
async function putBlob(env, vaultId, blobId, request) {
  const bytes = new Uint8Array(await request.arrayBuffer());
  const record = {
    content_type: request.headers.get("content-type") || "application/octet-stream",
    bytes_base64: bytesToBase64(bytes)
  };
  const key = blobPrefix + vaultId + ":" + blobId;
  if (env.KV && typeof env.KV.put === "function") {
    await env.KV.put(key, JSON.stringify(record));
  } else {
    memoryStates.set(key, record);
  }
  return json({ ok: true, blob_id: blobId });
}
async function getBlob(env, vaultId, blobId) {
  const key = blobPrefix + vaultId + ":" + blobId;
  let record = null;
  if (env.KV && typeof env.KV.get === "function") {
    record = await env.KV.get(key, { type: "json" });
  } else {
    record = memoryStates.get(key);
  }
  if (!record) {
    return json({ ok: false, error: "blob_not_found" }, { status: 404 });
  }
  return new Response(base64ToBytes(record.bytes_base64 || ""), {
    headers: {
      "content-type": record.content_type || "application/octet-stream"
    }
  });
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({
        ok: true,
        runtime_mode: "self_managed",
        artifact: "secondloop-local-qa-runtime",
        capabilities
      });
    }
    if (url.pathname === "/v1/runtime/model/verify-capabilities") {
      return json({
        ok: true,
        checks: checks.map((code) => ({ code, passed: true }))
      });
    }
    if (url.pathname === "/v1/runtime/capabilities") {
      return json({
        ok: true,
        runtime_mode: "self_managed",
        capabilities
      });
    }
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts[0] !== "v1" || parts[1] !== "runtime" || parts[2] !== "vaults") {
      return json({ ok: false, error: "not_found", path: url.pathname }, { status: 404 });
    }
    const vaultId = normalizeVaultId(parts[3]);
    const tail = parts.slice(4);
    if (tail[0] === "blobs" && tail.length === 2 && request.method === "PUT") {
      return putBlob(env, vaultId, decodeURIComponent(tail[1]), request);
    }
    if (tail[0] === "blobs" && tail.length === 2 && request.method === "GET") {
      return getBlob(env, vaultId, decodeURIComponent(tail[1]));
    }
    const state = await readState(env, vaultId);
    if (tail[0] === "conversations" && tail.length === 1 && request.method === "POST") {
      const conversationId = ensureConversation(state, "");
      await writeState(env, state);
      return json({ conversation_id: conversationId });
    }
    if (tail[0] === "conversations" && tail.length === 3 &&
        tail[2] === "messages" && request.method === "POST") {
      const conversationId = ensureConversation(state, decodeURIComponent(tail[1]));
      const body = await requestJson(request);
      const message = cleanText(body.message_display_text || body.message) ||
        (Array.isArray(body.attachments) && body.attachments.length > 0
          ? "发送了附件"
          : "");
      const userTurn = appendTurn(state, conversationId, "user", message, {
        attachment_refs: Array.isArray(body.attachments)
          ? body.attachments
              .map((item) => cleanText(item.attachment_id || item.id || item.sha256))
              .filter(Boolean)
          : []
      });
      const result = answerForMessage(state, conversationId, userTurn, body);
      await writeState(env, state);
      return json(result);
    }
    if (tail[0] === "agent-state" && tail.length === 1 && request.method === "GET") {
      const conversationId = ensureConversation(
        state,
        cleanText(url.searchParams.get("conversation_id"))
      );
      await writeState(env, state);
      return json(agentStateResponse(state, conversationId, url));
    }
    if (tail[0] === "approvals" && tail.length === 1 && request.method === "GET") {
      return json({ items: state.approval_items });
    }
    if (tail[0] === "approval-items" && tail.length === 2 && request.method === "PATCH") {
      const body = await requestJson(request);
      const approvalId = decodeURIComponent(tail[1]);
      const approval = state.approval_items.find((item) => item.id === approvalId);
      if (!approval) {
        return json({ ok: false, error: "approval_not_found" }, { status: 404 });
      }
      const changes = body.changes && typeof body.changes === "object" ? body.changes : {};
      if (cleanText(changes.title)) {
        approval.title = cleanText(changes.title);
        approval.record = { ...(approval.record || {}), title: approval.title };
      }
      approval.version = Number(approval.version || 1) + 1;
      await writeState(env, state);
      return json({ approval_item: approval });
    }
    if (tail[0] === "approvals" && tail[1] === "decision" && request.method === "POST") {
      const body = await requestJson(request);
      const approvalId = cleanText(body.approval_id);
      const decision = cleanText(body.decision) || "reject";
      const index = state.approval_items.findIndex((item) => item.id === approvalId);
      if (index < 0) {
        return json({ ok: true });
      }
      const approval = state.approval_items[index];
      const mutation = applyApproval(state, approval, decision);
      state.approval_items.splice(index, 1);
      const conversationId = ensureConversation(
        state,
        cleanText((approval.record || {}).conversation_id)
      );
      const assistantTurn = appendTurn(
        state,
        conversationId,
        "assistant",
        decision === "approve" ? "已确认并应用。" : "已取消这次变更。"
      );
      const result = makeRunResult(state, conversationId, assistantTurn, {
        response_type: decision === "approve" ? "approval_applied" : "approval_rejected",
        applied_mutations: mutation ? [mutation] : [],
        approval_items: state.approval_items
      });
      await writeState(env, state);
      return json(result);
    }
    if (tail[0] === "runs" && tail.length === 2 && request.method === "GET") {
      const run = state.runs[decodeURIComponent(tail[1])];
      return run ? json(run) : json({ ok: false, error: "run_not_found" }, { status: 404 });
    }
    if (tail[0] === "entity-focus" && tail.length === 1 && request.method === "POST") {
      const body = await requestJson(request);
      state.recent_entity_refs.push({
        conversation_id: cleanText(body.conversation_id),
        entity_type: cleanText(body.entity_type),
        entity_id: cleanText(body.entity_id),
        title: cleanText(body.title),
        source: "entity_viewed",
        created_at_ms: nowMs()
      });
      await writeState(env, state);
      return json({ ok: true });
    }
    return json({ ok: false, error: "not_found", path: url.pathname }, { status: 404 });
  }
};
''';
}
