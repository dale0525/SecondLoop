#[derive(Clone, Debug)]
struct TodoRecurrenceMeta {
    series_id: String,
    occurrence_index: i64,
    rule_json: String,
}

#[derive(Clone, Debug)]
struct RecurrenceRule {
    freq: String,
    interval: i64,
}

fn parse_recurrence_rule(rule_json: &str) -> Result<RecurrenceRule> {
    let value: serde_json::Value = serde_json::from_str(rule_json)
        .map_err(|e| anyhow!("invalid recurrence rule json: {e}"))?;
    let freq = value["freq"]
        .as_str()
        .ok_or_else(|| anyhow!("recurrence rule missing freq"))?
        .trim()
        .to_lowercase();
    if freq != "daily" && freq != "weekly" && freq != "monthly" && freq != "yearly" {
        return Err(anyhow!("unsupported recurrence freq: {freq}"));
    }

    let interval = value["interval"]
        .as_i64()
        .or_else(|| value["interval"].as_u64().and_then(|v| i64::try_from(v).ok()))
        .unwrap_or(1)
        .clamp(1, 10_000);

    Ok(RecurrenceRule { freq, interval })
}

fn is_leap_year(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

fn days_in_month(year: i32, month: time::Month) -> u8 {
    match month {
        time::Month::January => 31,
        time::Month::February => {
            if is_leap_year(year) {
                29
            } else {
                28
            }
        }
        time::Month::March => 31,
        time::Month::April => 30,
        time::Month::May => 31,
        time::Month::June => 30,
        time::Month::July => 31,
        time::Month::August => 31,
        time::Month::September => 30,
        time::Month::October => 31,
        time::Month::November => 30,
        time::Month::December => 31,
    }
}

fn add_months_utc_ms(base_ms: i64, month_delta: i32) -> Result<i64> {
    let base_secs = base_ms.div_euclid(1000);
    let ms_remainder = base_ms.rem_euclid(1000);
    let dt = time::OffsetDateTime::from_unix_timestamp(base_secs)
        .map_err(|e| anyhow!("invalid base timestamp: {e}"))?;

    let base_year = dt.year();
    let base_month = dt.month() as i32;
    let total_month = (base_year * 12 + (base_month - 1))
        .checked_add(month_delta)
        .ok_or_else(|| anyhow!("recurrence month overflow"))?;
    let new_year = total_month.div_euclid(12);
    let new_month_index = total_month.rem_euclid(12) + 1;
    let new_month = time::Month::try_from(new_month_index as u8)
        .map_err(|_| anyhow!("invalid month after recurrence add"))?;

    let day = dt.day().min(days_in_month(new_year, new_month));
    let new_date = time::Date::from_calendar_date(new_year, new_month, day)
        .map_err(|e| anyhow!("invalid recurrence date: {e}"))?;
    let new_dt = time::PrimitiveDateTime::new(new_date, dt.time()).assume_utc();

    Ok(new_dt.unix_timestamp() * 1000 + ms_remainder)
}

fn next_due_at_ms(base_due_at_ms: i64, rule_json: &str) -> Result<i64> {
    let rule = parse_recurrence_rule(rule_json)?;
    let interval_days = rule.interval.saturating_mul(24 * 60 * 60 * 1000);

    match rule.freq.as_str() {
        "daily" => base_due_at_ms
            .checked_add(interval_days)
            .ok_or_else(|| anyhow!("daily recurrence overflow")),
        "weekly" => base_due_at_ms
            .checked_add(interval_days.saturating_mul(7))
            .ok_or_else(|| anyhow!("weekly recurrence overflow")),
        "monthly" => {
            let months = i32::try_from(rule.interval)
                .map_err(|_| anyhow!("monthly interval overflow"))?;
            add_months_utc_ms(base_due_at_ms, months)
        }
        "yearly" => {
            let months = i32::try_from(rule.interval.saturating_mul(12))
                .map_err(|_| anyhow!("yearly interval overflow"))?;
            add_months_utc_ms(base_due_at_ms, months)
        }
        _ => Err(anyhow!("unsupported recurrence freq")),
    }
}

fn get_todo_recurrence_meta(conn: &Connection, todo_id: &str) -> Result<Option<TodoRecurrenceMeta>> {
    conn.query_row(
        r#"
SELECT r.series_id, r.occurrence_index, s.rule_json
FROM todo_recurrences r
JOIN todo_series s ON s.id = r.series_id
WHERE r.todo_id = ?1
"#,
        params![todo_id],
        |row| {
            Ok(TodoRecurrenceMeta {
                series_id: row.get(0)?,
                occurrence_index: row.get(1)?,
                rule_json: row.get(2)?,
            })
        },
    )
    .optional()
    .map_err(|e| anyhow!("failed to load todo recurrence meta: {e}"))
}

pub fn get_todo_recurrence_rule_json(conn: &Connection, todo_id: &str) -> Result<Option<String>> {
    Ok(get_todo_recurrence_meta(conn, todo_id)?.map(|meta| meta.rule_json))
}

pub fn upsert_todo_recurrence(
    conn: &Connection,
    todo_id: &str,
    series_id: &str,
    rule_json: &str,
) -> Result<()> {
    let _ = parse_recurrence_rule(rule_json)?;
    let now = now_ms();

    conn.execute(
        r#"
INSERT INTO todo_series(id, rule_json, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(id) DO UPDATE SET
  rule_json = excluded.rule_json,
  updated_at_ms = excluded.updated_at_ms
"#,
        params![series_id, rule_json, now, now],
    )?;

    let existing_occurrence: Option<i64> = conn
        .query_row(
            r#"SELECT occurrence_index FROM todo_recurrences WHERE todo_id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;
    let occurrence_index: i64 = if let Some(existing) = existing_occurrence {
        existing
    } else {
        conn.query_row(
            r#"SELECT COALESCE(MAX(occurrence_index), -1) + 1
               FROM todo_recurrences
               WHERE series_id = ?1"#,
            params![series_id],
            |row| row.get(0),
        )?
    };

    conn.execute(
        r#"
INSERT INTO todo_recurrences(todo_id, series_id, occurrence_index, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, ?4, ?5)
ON CONFLICT(todo_id) DO UPDATE SET
  series_id = excluded.series_id,
  occurrence_index = excluded.occurrence_index,
  updated_at_ms = excluded.updated_at_ms
"#,
        params![todo_id, series_id, occurrence_index, now, now],
    )?;

    Ok(())
}

fn maybe_spawn_next_recurring_todo(
    conn: &Connection,
    key: &[u8; 32],
    todo: &Todo,
    new_status: &str,
) -> Result<()> {
    if new_status != "done" {
        return Ok(());
    }

    let Some(base_due_at_ms) = todo.due_at_ms else {
        return Ok(());
    };
    let Some(meta) = get_todo_recurrence_meta(conn, &todo.id)? else {
        return Ok(());
    };

    let next_index = meta.occurrence_index.saturating_add(1);
    let existing_next: Option<String> = conn
        .query_row(
            r#"SELECT todo_id FROM todo_recurrences WHERE series_id = ?1 AND occurrence_index = ?2"#,
            params![meta.series_id, next_index],
            |row| row.get(0),
        )
        .optional()?;
    if existing_next.is_some() {
        return Ok(());
    }

    let next_due_at_ms = next_due_at_ms(base_due_at_ms, &meta.rule_json)?;
    let next_todo_id = format!("todo:{}:{}", meta.series_id, next_index);

    let _ = upsert_todo(
        conn,
        key,
        &next_todo_id,
        &todo.title,
        Some(next_due_at_ms),
        "open",
        todo.source_entry_id.as_deref(),
        None,
        None,
        Some(now_ms()),
    )?;

    conn.execute(
        r#"
INSERT OR IGNORE INTO todo_recurrences(todo_id, series_id, occurrence_index, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, ?4, ?5)
"#,
        params![next_todo_id, meta.series_id, next_index, now_ms(), now_ms()],
    )?;

    Ok(())
}
