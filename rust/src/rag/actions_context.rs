use anyhow::Result;
use rusqlite::Connection;

use crate::db;
use crate::message_citations::AnswerEvidenceDirectSource;

use super::evidence::{build_event_direct_source, build_todo_direct_source};

const ACTION_CONTEXT_LIMIT: usize = 40;
const HOUR_MS: i64 = 60 * 60 * 1000;
const DAY_MS: i64 = 24 * HOUR_MS;

#[derive(Clone, Debug, Default)]
pub(super) struct ActionContextBundle {
    pub(super) text: String,
    pub(super) direct_sources: Vec<AnswerEvidenceDirectSource>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AgendaTimeframe {
    Today,
    Tomorrow,
    ThisWeek,
    NextWeek,
    ImplicitAgenda,
}

#[derive(Clone, Debug)]
struct ActionContextEntry {
    sort_at_ms: i64,
    stable_key: String,
    text: String,
    direct_source: AnswerEvidenceDirectSource,
}

pub(super) fn should_include_actions_context(question: &str) -> bool {
    agenda_horizon_ms(question, 0).is_some()
}

pub(super) fn should_include_actions_context_in_range(question: &str) -> bool {
    has_explicit_agenda_intent(question)
        || has_generic_task_words(question)
        || has_past_actions_intent(question)
}

pub(super) fn build_actions_context(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
) -> Result<Option<ActionContextBundle>> {
    if !should_include_actions_context(question) {
        return Ok(None);
    }

    let now = now_ms();
    let Some(horizon) = agenda_horizon_ms(question, now) else {
        return Ok(None);
    };
    let mut entries: Vec<ActionContextEntry> = Vec::new();

    for todo in db::list_todos(conn, key)? {
        if todo.status == "done" || todo.status == "dismissed" {
            continue;
        }

        let due = todo.due_at_ms;
        let review = todo.next_review_at_ms;
        let is_due = due.is_some_and(|ms| ms <= horizon);
        let is_review_due = review.is_some_and(|ms| ms <= horizon);
        if !is_due && !is_review_due {
            continue;
        }

        let mut item = format!("TODO [{}] {}", todo.status, todo.title);
        if let Some(ms) = due {
            item.push_str(&format!(" (due_at_ms={ms})"));
        }
        if let Some(ms) = review {
            item.push_str(&format!(" (next_review_at_ms={ms})"));
        }
        let sort_at_ms = match (due, review) {
            (Some(due), Some(review)) => due.min(review),
            (Some(due), None) => due,
            (None, Some(review)) => review,
            (None, None) => continue,
        };
        entries.push(ActionContextEntry {
            sort_at_ms,
            stable_key: format!("todo:{}", todo.id),
            text: item.clone(),
            direct_source: build_todo_direct_source(&todo, &item, todo.created_at_ms),
        });
    }

    for event in db::list_events(conn, key)? {
        if event.end_at_ms < now {
            continue;
        }
        if event.start_at_ms > horizon {
            continue;
        }
        let text = format!(
            "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
            event.title, event.start_at_ms, event.end_at_ms, event.tz
        );
        entries.push(ActionContextEntry {
            sort_at_ms: event.start_at_ms.max(now),
            stable_key: format!("event:{}", event.id),
            text,
            direct_source: build_event_direct_source(&event),
        });
    }

    Ok(render_action_context(
        "Upcoming actions (from local todos/events):",
        entries,
        false,
    ))
}

pub(super) fn build_actions_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Option<ActionContextBundle>> {
    if !should_include_actions_context_in_range(question) {
        return Ok(None);
    }

    if has_past_actions_intent(question) {
        return build_past_actions_context_in_range(conn, key, time_start_ms, time_end_ms);
    }

    build_upcoming_actions_context_in_range(conn, key, time_start_ms, time_end_ms)
}

fn now_ms() -> i64 {
    crate::platform::time::now_ms()
}

fn agenda_horizon_ms(question: &str, now_ms: i64) -> Option<i64> {
    let timeframe = detect_agenda_timeframe(question)?;
    Some(match timeframe {
        AgendaTimeframe::Today => now_ms.saturating_add(36 * HOUR_MS),
        AgendaTimeframe::Tomorrow => now_ms.saturating_add(60 * HOUR_MS),
        AgendaTimeframe::ThisWeek | AgendaTimeframe::ImplicitAgenda => {
            now_ms.saturating_add(8 * DAY_MS)
        }
        AgendaTimeframe::NextWeek => now_ms.saturating_add(15 * DAY_MS),
    })
}

fn detect_agenda_timeframe(question: &str) -> Option<AgendaTimeframe> {
    let q = question.trim().to_lowercase();
    if q.is_empty() {
        return None;
    }

    let has_explicit_intent = has_explicit_agenda_intent(question);
    if !(has_explicit_intent
        || (has_generic_task_words(question) && has_future_actions_timeframe(question)))
    {
        return None;
    }

    if has_today_timeframe(question) {
        return Some(AgendaTimeframe::Today);
    }
    if has_tomorrow_timeframe(question) {
        return Some(AgendaTimeframe::Tomorrow);
    }
    if has_this_week_timeframe(question) {
        return Some(AgendaTimeframe::ThisWeek);
    }
    if has_next_week_timeframe(question) {
        return Some(AgendaTimeframe::NextWeek);
    }
    if has_explicit_intent {
        return Some(AgendaTimeframe::ImplicitAgenda);
    }

    None
}

fn has_today_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("today")
        || q.contains("tonight")
        || q.contains("today's")
        || question.contains("今天")
        || question.contains("今日")
}

fn has_tomorrow_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("tomorrow") || question.contains("明天")
}

fn has_this_week_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("this week")
        || q.contains("week agenda")
        || q.contains("weekly agenda")
        || q.contains("this week's")
        || question.contains("本周")
        || question.contains("这周")
        || question.contains("這週")
}

fn has_next_week_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("next week") || question.contains("下周") || question.contains("下週")
}

fn has_future_actions_timeframe(question: &str) -> bool {
    has_today_timeframe(question)
        || has_tomorrow_timeframe(question)
        || has_this_week_timeframe(question)
        || has_next_week_timeframe(question)
}

fn has_explicit_agenda_intent(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("agenda")
        || q.contains("schedule")
        || q.contains("calendar")
        || q.contains("todo")
        || q.contains("to-do")
        || q.contains("priority")
        || q.contains("priorities")
        || q.contains("what should i do")
        || q.contains("what do i need to do")
        || q.contains("what's on my schedule")
        || q.contains("what is on my schedule")
        || q.contains("what's on my calendar")
        || q.contains("what is on my calendar")
        || q.contains("upcoming")
        || q.contains("due today")
        || question.contains("待办")
        || question.contains("待辦")
        || question.contains("日程")
        || question.contains("行程")
        || question.contains("安排")
        || question.contains("提醒")
        || question.contains("优先级")
        || question.contains("優先級")
        || question.contains("要做")
        || question.contains("该做什么")
        || question.contains("該做什麼")
        || question.contains("有哪些事")
}

fn has_generic_task_words(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("task")
        || q.contains("tasks")
        || question.contains("任务")
        || question.contains("任務")
        || question.contains("计划")
        || question.contains("計劃")
}

fn has_past_actions_intent(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("what did i do")
        || q.contains("what have i done")
        || q.contains("what did i finish")
        || q.contains("what have i finished")
        || question.contains("做了什么")
        || question.contains("做了哪些事")
        || question.contains("完成了什么")
}

fn should_prefer_past_action_activity(
    candidate: &db::TodoActivity,
    current: &db::TodoActivity,
) -> bool {
    let candidate_is_done = candidate.to_status.as_deref() == Some("done");
    let current_is_done = current.to_status.as_deref() == Some("done");
    if candidate_is_done != current_is_done {
        return candidate_is_done;
    }

    if candidate.created_at_ms != current.created_at_ms {
        return candidate.created_at_ms > current.created_at_ms;
    }

    candidate.id > current.id
}

fn render_action_context(
    header: &str,
    mut entries: Vec<ActionContextEntry>,
    newest_first: bool,
) -> Option<ActionContextBundle> {
    if entries.is_empty() {
        return None;
    }

    entries.sort_by(|left, right| {
        if left.sort_at_ms != right.sort_at_ms {
            let ordering = left.sort_at_ms.cmp(&right.sort_at_ms);
            return if newest_first {
                ordering.reverse()
            } else {
                ordering
            };
        }

        left.stable_key.cmp(&right.stable_key)
    });

    let mut text = String::new();
    text.push_str(header);
    text.push('\n');
    let mut direct_sources = Vec::<AnswerEvidenceDirectSource>::new();
    for entry in entries.into_iter().take(ACTION_CONTEXT_LIMIT) {
        text.push_str("- ");
        text.push_str(&entry.text);
        text.push('\n');
        direct_sources.push(entry.direct_source);
    }
    Some(ActionContextBundle {
        text,
        direct_sources,
    })
}

fn build_upcoming_actions_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Option<ActionContextBundle>> {
    let mut entries: Vec<ActionContextEntry> = Vec::new();

    for todo in db::list_todos(conn, key)? {
        if todo.status == "dismissed" || todo.status == "done" {
            continue;
        }

        let due_in_range = todo
            .due_at_ms
            .is_some_and(|ms| ms >= time_start_ms && ms < time_end_ms);
        let review_in_range = todo
            .next_review_at_ms
            .is_some_and(|ms| ms >= time_start_ms && ms < time_end_ms);
        if !due_in_range && !review_in_range {
            continue;
        }

        let mut item = format!("TODO [{}] {}", todo.status, todo.title);
        if let Some(ms) = todo.due_at_ms {
            item.push_str(&format!(" (due_at_ms={ms})"));
        }
        if let Some(ms) = todo.next_review_at_ms {
            item.push_str(&format!(" (next_review_at_ms={ms})"));
        }
        let sort_at_ms = match (todo.due_at_ms, todo.next_review_at_ms) {
            (Some(due), Some(review)) => due.min(review),
            (Some(due), None) => due,
            (None, Some(review)) => review,
            (None, None) => continue,
        };
        entries.push(ActionContextEntry {
            sort_at_ms,
            stable_key: format!("todo:{}", todo.id),
            text: item.clone(),
            direct_source: build_todo_direct_source(&todo, &item, todo.created_at_ms),
        });
    }

    for event in db::list_events(conn, key)? {
        let overlaps_range = event.end_at_ms > time_start_ms && event.start_at_ms < time_end_ms;
        if !overlaps_range {
            continue;
        }
        let text = format!(
            "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
            event.title, event.start_at_ms, event.end_at_ms, event.tz
        );
        entries.push(ActionContextEntry {
            sort_at_ms: event.start_at_ms.max(time_start_ms),
            stable_key: format!("event:{}", event.id),
            text,
            direct_source: build_event_direct_source(&event),
        });
    }

    Ok(render_action_context(
        "Upcoming actions (from local todos/events):",
        entries,
        false,
    ))
}

fn build_past_actions_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Option<ActionContextBundle>> {
    let mut entries: Vec<ActionContextEntry> = Vec::new();
    let mut selected_activity_by_todo =
        std::collections::HashMap::<String, db::TodoActivity>::new();

    for activity in db::list_todo_activities_in_range(conn, key, time_start_ms, time_end_ms)? {
        let should_replace = selected_activity_by_todo
            .get(&activity.todo_id)
            .map(|current| should_prefer_past_action_activity(&activity, current))
            .unwrap_or(true);
        if should_replace {
            selected_activity_by_todo.insert(activity.todo_id.clone(), activity);
        }
    }

    for activity in selected_activity_by_todo.into_values() {
        let todo = match db::get_todo(conn, key, &activity.todo_id) {
            Ok(value) => value,
            Err(_) => continue,
        };

        let line = match activity.to_status.as_deref() {
            Some("done") => format!(
                "TODO [done] {} (completed_at_ms={})",
                todo.title, activity.created_at_ms
            ),
            _ => {
                let activity_status = activity
                    .to_status
                    .as_deref()
                    .or(activity.from_status.as_deref());
                let activity_prefix = activity_status
                    .map(|status| format!("TODO_ACTIVITY [{status}] {}", todo.title))
                    .unwrap_or_else(|| format!("TODO_ACTIVITY {}", todo.title));
                match activity.content.as_deref() {
                    Some(content) if !content.trim().is_empty() => format!(
                        "{activity_prefix} (created_at_ms={}) content={}",
                        activity.created_at_ms, content
                    ),
                    _ => format!(
                        "{activity_prefix} (created_at_ms={}) type={}",
                        activity.created_at_ms, activity.activity_type
                    ),
                }
            }
        };
        let snippet_source = activity
            .content
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| line.clone());
        entries.push(ActionContextEntry {
            sort_at_ms: activity.created_at_ms,
            stable_key: format!("todo:{}", todo.id),
            text: line,
            direct_source: build_todo_direct_source(&todo, &snippet_source, activity.created_at_ms),
        });
    }

    for event in db::list_events_in_range(conn, key, time_start_ms, time_end_ms)? {
        let text = format!(
            "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
            event.title, event.start_at_ms, event.end_at_ms, event.tz
        );
        entries.push(ActionContextEntry {
            sort_at_ms: event.end_at_ms.min(time_end_ms.saturating_sub(1)),
            stable_key: format!("event:{}", event.id),
            text,
            direct_source: build_event_direct_source(&event),
        });
    }

    Ok(render_action_context(
        "Past actions (from local todos/events):",
        entries,
        true,
    ))
}
