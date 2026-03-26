use anyhow::{anyhow, Result};
use rusqlite::Connection;

use crate::{
    db,
    embedding::{BrokEmbedder, CloudGatewayEmbedder, Embedder},
};

pub(crate) fn guess_initial_remote_embedding_dim(
    conn: &Connection,
    model_name: &str,
) -> Result<Option<usize>> {
    db::lookup_embedding_space_dim(conn, model_name)
}

pub(crate) fn seed_cloud_gateway_embedder_from_cache(
    conn: &Connection,
    gateway_base_url: &str,
    requested_model_name: &str,
    embedder: &CloudGatewayEmbedder,
) -> Result<bool> {
    let Some(cache) = db::load_cloud_gateway_embeddings_cache(conn)? else {
        return Ok(false);
    };
    if cache.base_url != gateway_base_url || cache.requested_model_name != requested_model_name {
        return Ok(false);
    }
    embedder.seed_effective_model_id_and_dim(&cache.effective_model_id, cache.dim);
    Ok(true)
}

pub(crate) fn should_reset_cloud_gateway_cache_seed(message: &str) -> bool {
    message.contains("cloud-gateway embedding model_id mismatch")
        || message.contains("cloud-gateway embedding dim mismatch")
}

pub(crate) fn is_remote_embedding_retryable(message: &str) -> bool {
    should_reset_cloud_gateway_cache_seed(message) || message.contains("embedder dim mismatch")
}

pub(crate) fn store_cloud_gateway_cache_if_learned(
    conn: &Connection,
    gateway_base_url: &str,
    requested_model_name: &str,
    embedder: &CloudGatewayEmbedder,
) -> Result<()> {
    let Some(dim) = embedder.learned_dim() else {
        return Ok(());
    };
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }
    let effective_model_name = embedder
        .learned_model_name()
        .unwrap_or(embedder.model_name())
        .trim();
    if effective_model_name.is_empty() {
        return Ok(());
    }
    db::store_cloud_gateway_embeddings_cache(
        conn,
        gateway_base_url,
        requested_model_name,
        effective_model_name,
        dim,
    )
}

pub(crate) fn activate_remote_embedder_if_learned<E, F>(
    conn: &Connection,
    embedder: &E,
    learned_dim: F,
) -> Result<()>
where
    E: Embedder + ?Sized,
    F: Fn(&E) -> Option<usize> + Copy,
{
    let Some(dim) = learned_dim(embedder) else {
        return Ok(());
    };
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }
    db::set_active_embedding_model(conn, embedder.model_name(), dim)?;
    Ok(())
}

fn learn_remote_embedding_dim_from_probe<E, F>(embedder: &E, learned_dim: F) -> Result<usize>
where
    E: Embedder + ?Sized,
    F: Fn(&E) -> Option<usize> + Copy,
{
    let probe = embedder.embed(&["probe".to_string()])?;
    let dim = learned_dim(embedder).unwrap_or_else(|| probe.first().map(|v| v.len()).unwrap_or(0));
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("remote embedder returned empty probe embeddings"));
    }
    Ok(dim)
}

fn process_pending_remote_todo_thread_embeddings_once<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    todo_limit: usize,
    activity_limit: usize,
) -> Result<u32> {
    let todos = db::process_pending_todo_embeddings(conn, key, embedder, todo_limit)?;
    let activities =
        db::process_pending_todo_activity_embeddings(conn, key, embedder, activity_limit)?;
    Ok(todos.saturating_add(activities) as u32)
}

pub(crate) fn process_pending_remote_todo_thread_embeddings<E, F>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    todo_limit: usize,
    activity_limit: usize,
    initial_dim: Option<usize>,
    learned_dim: F,
) -> Result<u32>
where
    E: Embedder + ?Sized,
    F: Fn(&E) -> Option<usize> + Copy,
{
    let initial_dim = match initial_dim {
        Some(dim) => Some(dim),
        None => Some(learn_remote_embedding_dim_from_probe(
            embedder,
            learned_dim,
        )?),
    };

    if let Some(dim) = initial_dim {
        db::set_active_embedding_model(conn, embedder.model_name(), dim)?;
    }

    match process_pending_remote_todo_thread_embeddings_once(
        conn,
        key,
        embedder,
        todo_limit,
        activity_limit,
    ) {
        Ok(count) => {
            activate_remote_embedder_if_learned(conn, embedder, learned_dim)?;
            Ok(count)
        }
        Err(err) => {
            let message = err.to_string();
            if !is_remote_embedding_retryable(&message) {
                return Err(err);
            }
            let Some(actual_dim) = learned_dim(embedder) else {
                return Err(err);
            };
            if actual_dim == 0 || actual_dim > 8192 || Some(actual_dim) == initial_dim {
                return Err(err);
            }
            db::set_active_embedding_model(conn, embedder.model_name(), actual_dim)?;
            let count = process_pending_remote_todo_thread_embeddings_once(
                conn,
                key,
                embedder,
                todo_limit,
                activity_limit,
            )?;
            activate_remote_embedder_if_learned(conn, embedder, learned_dim)?;
            Ok(count)
        }
    }
}

pub(crate) fn process_cloud_gateway_pending_todo_thread_embeddings(
    conn: &Connection,
    key: &[u8; 32],
    todo_limit: usize,
    activity_limit: usize,
    gateway_base_url: &str,
    firebase_id_token: &str,
    requested_model_name: &str,
) -> Result<u32> {
    let embedder = CloudGatewayEmbedder::new(
        gateway_base_url.to_string(),
        firebase_id_token.to_string(),
        requested_model_name.to_string(),
    );
    let used_cache = seed_cloud_gateway_embedder_from_cache(
        conn,
        gateway_base_url,
        requested_model_name,
        &embedder,
    )?;
    let initial_dim = if used_cache {
        embedder.learned_dim()
    } else {
        guess_initial_remote_embedding_dim(conn, embedder.model_name())?
    };

    match process_pending_remote_todo_thread_embeddings(
        conn,
        key,
        &embedder,
        todo_limit,
        activity_limit,
        initial_dim,
        CloudGatewayEmbedder::learned_dim,
    ) {
        Ok(count) => {
            store_cloud_gateway_cache_if_learned(
                conn,
                gateway_base_url,
                requested_model_name,
                &embedder,
            )?;
            Ok(count)
        }
        Err(err) => {
            if !used_cache || !should_reset_cloud_gateway_cache_seed(&err.to_string()) {
                return Err(err);
            }
            let fresh = CloudGatewayEmbedder::new(
                gateway_base_url.to_string(),
                firebase_id_token.to_string(),
                requested_model_name.to_string(),
            );
            let fresh_initial_dim = guess_initial_remote_embedding_dim(conn, fresh.model_name())?;
            let count = process_pending_remote_todo_thread_embeddings(
                conn,
                key,
                &fresh,
                todo_limit,
                activity_limit,
                fresh_initial_dim,
                CloudGatewayEmbedder::learned_dim,
            )?;
            store_cloud_gateway_cache_if_learned(
                conn,
                gateway_base_url,
                requested_model_name,
                &fresh,
            )?;
            Ok(count)
        }
    }
}

pub(crate) fn process_brok_pending_todo_thread_embeddings(
    conn: &Connection,
    key: &[u8; 32],
    todo_limit: usize,
    activity_limit: usize,
    base_url: &str,
    api_key: &str,
    model_name: &str,
) -> Result<u32> {
    let embedder = BrokEmbedder::new(
        base_url.to_string(),
        api_key.to_string(),
        model_name.to_string(),
    );
    let initial_dim = guess_initial_remote_embedding_dim(conn, embedder.model_name())?;
    process_pending_remote_todo_thread_embeddings(
        conn,
        key,
        &embedder,
        todo_limit,
        activity_limit,
        initial_dim,
        BrokEmbedder::learned_dim,
    )
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn uses_known_embedding_space_dim_as_probe_free_hint() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open db");
        db::set_active_embedding_model(&conn, "model-a", 1024).expect("seed dim");

        let dim = guess_initial_remote_embedding_dim(&conn, "model-a").expect("guess dim");

        assert_eq!(dim, Some(1024));
    }

    #[test]
    fn seeds_cloud_gateway_embedder_from_matching_cache() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open db");
        db::store_cloud_gateway_embeddings_cache(
            &conn,
            "https://gateway.test",
            "text-embed",
            "text-embed-effective",
            1536,
        )
        .expect("store cache");
        let embedder = CloudGatewayEmbedder::new(
            "https://gateway.test".to_string(),
            "token".to_string(),
            "text-embed".to_string(),
        );

        let used_cache = seed_cloud_gateway_embedder_from_cache(
            &conn,
            "https://gateway.test",
            "text-embed",
            &embedder,
        )
        .expect("seed cache");

        assert!(used_cache);
        assert_eq!(embedder.learned_dim(), Some(1536));
        assert_eq!(embedder.model_name(), "text-embed-effective");
    }

    #[test]
    fn store_cloud_gateway_cache_requires_real_learned_dim() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open db");
        let embedder = CloudGatewayEmbedder::new(
            "https://gateway.test".to_string(),
            "token".to_string(),
            "text-embed".to_string(),
        );

        store_cloud_gateway_cache_if_learned(
            &conn,
            "https://gateway.test",
            "text-embed",
            &embedder,
        )
        .expect("store noop");

        assert!(db::load_cloud_gateway_embeddings_cache(&conn)
            .expect("load cache")
            .is_none());
    }

    #[test]
    fn retryable_messages_cover_cache_seed_reset_and_dim_mismatch() {
        assert!(should_reset_cloud_gateway_cache_seed(
            "cloud-gateway embedding model_id mismatch: expected a, got b"
        ));
        assert!(is_remote_embedding_retryable(
            "embedder dim mismatch: expected 384, got 1536"
        ));
        assert!(!is_remote_embedding_retryable("request failed: HTTP 401"));
    }
}
