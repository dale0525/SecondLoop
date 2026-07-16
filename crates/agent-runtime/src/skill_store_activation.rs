use super::SkillRevisionStore;
use crate::skill_source::{
    DiscoveredSkillPackage, ManagedExecutionBinding, SkillLayer, VerifiedPackageContent,
};
use crate::skill_state::{SkillRevisionExpectation, SkillRevisionPromotion, SkillRevisionRecord};
use crate::skill_store_faults::StoreFaultPoint;
use crate::skill_store_fs::{copy_prepared_package_tree_into_prepared, make_tree_readonly};
use crate::skill_store_locks::{RevisionOperationGuard, acquire_revision_lock};
use crate::skill_store_operations::{combine_operation_errors, storage_path};
use crate::skill_store_public_types::SkillStoreBoundaryError;
use crate::skill_store_secure_roots::{
    PreparedStoreDirectory, ensure_directory, open_prepared_directory, opened_package_snapshot,
    reserve_opened_directory,
};
use std::path::{Path, PathBuf};
use std::sync::Arc;

pub(crate) struct PreparedManagedActivation {
    store: SkillRevisionStore,
    record: SkillRevisionRecord,
    expectation: SkillRevisionExpectation,
    promotion: SkillRevisionPromotion,
    candidate: DiscoveredSkillPackage,
    source: PreparedStoreDirectory,
    destination: PreparedStoreDirectory,
    destination_path: PathBuf,
    _revision_lock: RevisionOperationGuard,
}

impl SkillRevisionStore {
    pub(crate) async fn verify_managed_binding(
        &self,
        package_id: &crate::skill_package::SkillPackageId,
        revision_id: &str,
        storage_path: &std::path::Path,
        expected_hash: &str,
    ) -> anyhow::Result<()> {
        self.paths.verify_identity()?;
        let record = self
            .state
            .get_revision(revision_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("managed revision not found"))?;
        if record.status != crate::skill_state::SkillRevisionStatus::Managed
            || record.package_id != *package_id
            || record.content_hash != expected_hash
            || std::path::Path::new(&record.storage_path) != storage_path
        {
            anyhow::bail!("managed revision binding changed");
        }
        let relative = PathBuf::from(package_id.as_str())
            .join("revisions")
            .join(revision_id);
        let directory = open_prepared_directory(self.paths.managed_identity(), &relative).await?;
        let snapshot = opened_package_snapshot(&directory, self.limits.package_limits()).await?;
        directory.verify()?;
        if snapshot.content_hash != expected_hash {
            anyhow::bail!("managed revision content changed");
        }
        Ok(())
    }

    pub(crate) async fn prepare_managed_activation(
        &self,
        revision_id: &str,
        expectation: SkillRevisionExpectation,
    ) -> anyhow::Result<PreparedManagedActivation> {
        let revision_lock =
            acquire_revision_lock(&self.paths.identity, revision_id, &self.faults).await?;
        let record = self.state.get_revision(revision_id).await?.ok_or_else(|| {
            SkillStoreBoundaryError::NotFound(anyhow::anyhow!("skill revision not found"))
        })?;
        expectation_record(revision_id, &record, &expectation)?;
        self.paths.verify_identity()?;
        let (_, source_relative) = self.staging_revision_path(&record)?;
        let source =
            open_prepared_directory(self.paths.staging_identity(), &source_relative).await?;
        let metadata = self.final_metadata(&record, &source).await?;
        if metadata.content_hash != expectation.content_hash
            || metadata.descriptor_json != expectation.descriptor_json
            || metadata.validation_json != expectation.validation_json
            || metadata.version != expectation.version
        {
            return Err(SkillStoreBoundaryError::Conflict(anyhow::anyhow!(
                "activation approval is stale"
            ))
            .into());
        }

        let package_relative = PathBuf::from(record.package_id.as_str()).join("revisions");
        ensure_directory(self.paths.managed_identity(), &package_relative).await?;
        let destination_relative = package_relative.join(revision_id);
        let destination_path = self.paths.managed.join(&destination_relative);
        let destination_storage = storage_path(&destination_path)?;
        let destination =
            reserve_opened_directory(self.paths.managed_identity(), &destination_relative)
                .await
                .map_err(|error| {
                    if is_already_exists(&error) {
                        SkillStoreBoundaryError::Conflict(error).into()
                    } else {
                        error
                    }
                })?;
        let prepare_result = async {
            copy_prepared_package_tree_into_prepared(
                &source,
                &destination,
                self.limits.package_limits(),
                &self.faults,
                StoreFaultPoint::IncomingCopyFile,
            )
            .await?;
            let snapshot =
                opened_package_snapshot(&destination, self.limits.package_limits()).await?;
            if snapshot.content_hash != metadata.content_hash {
                anyhow::bail!("prepared activation copy hash mismatch");
            }
            make_tree_readonly(&destination, self.limits.package_limits()).await?;
            destination.verify()?;
            let candidate = DiscoveredSkillPackage {
                layer: SkillLayer::Managed,
                root: destination_path.clone(),
                descriptor: snapshot.descriptor.descriptor,
                content_hash: snapshot.content_hash.clone(),
                warnings: snapshot.descriptor.warnings,
                verified_content: Some(VerifiedPackageContent {
                    runtime_manifest: snapshot.runtime_manifest.map(Arc::from),
                    instructions_file: snapshot.instructions_file.map(Arc::from),
                    file_paths: Arc::new(snapshot.file_paths),
                    expected_content_hash: snapshot.content_hash,
                    limits: self.limits,
                    execution_binding: Some(ManagedExecutionBinding {
                        store: self.clone(),
                        package_id: record.package_id.clone(),
                        revision_id: record.revision_id.clone(),
                        storage_path: destination_path.clone(),
                    }),
                    bundle_execution_binding: None,
                }),
            };
            Ok(candidate)
        }
        .await;
        let candidate = match prepare_result {
            Ok(candidate) => candidate,
            Err(error) => {
                let cleanup = self
                    .cleanup_failed_promotion_destination(&destination)
                    .await;
                return Err(combine_operation_errors(
                    error,
                    [("prepared activation cleanup", cleanup)],
                ));
            }
        };
        let promotion = SkillRevisionPromotion {
            version: metadata.version,
            content_hash: metadata.content_hash,
            storage_path: destination_storage,
            descriptor_json: metadata.descriptor_json,
            validation_json: metadata.validation_json,
        };
        self.faults
            .checkpoint(StoreFaultPoint::ActivationAfterPrepare)
            .await;
        Ok(PreparedManagedActivation {
            store: self.clone(),
            record,
            expectation,
            promotion,
            candidate,
            source,
            destination,
            destination_path,
            _revision_lock: revision_lock,
        })
    }
}

impl PreparedManagedActivation {
    pub(crate) fn expectation(&self) -> &SkillRevisionExpectation {
        &self.expectation
    }

    pub(crate) fn promotion(&self) -> &SkillRevisionPromotion {
        &self.promotion
    }

    pub(crate) fn candidate(&self) -> DiscoveredSkillPackage {
        self.candidate.clone()
    }

    pub(crate) async fn revalidate_destination(&self) -> anyhow::Result<()> {
        self.store.paths.verify_identity()?;
        self.destination
            .verify()
            .map_err(SkillStoreBoundaryError::Conflict)?;
        let snapshot =
            opened_package_snapshot(&self.destination, self.store.limits.package_limits())
                .await
                .map_err(SkillStoreBoundaryError::Conflict)?;
        self.destination
            .verify()
            .map_err(SkillStoreBoundaryError::Conflict)?;
        let descriptor_json = serde_json::to_value(&snapshot.descriptor.descriptor)?;
        let binding = self
            .candidate
            .verified_content
            .as_ref()
            .and_then(|content| content.execution_binding.as_ref())
            .ok_or_else(|| {
                SkillStoreBoundaryError::Conflict(anyhow::anyhow!(
                    "prepared activation has no execution binding"
                ))
            })?;
        let exact = snapshot.descriptor.descriptor.id == self.record.package_id
            && snapshot.descriptor.descriptor.version.to_string() == self.expectation.version
            && snapshot.descriptor.descriptor.kind == self.candidate.descriptor.kind
            && descriptor_json == self.expectation.descriptor_json
            && snapshot.content_hash == self.expectation.content_hash
            && snapshot.content_hash == self.candidate.content_hash
            && self.candidate.root == self.destination_path
            && binding.package_id == self.record.package_id
            && binding.revision_id == self.record.revision_id
            && binding.storage_path == self.destination_path
            && binding.store.paths.identity == self.store.paths.identity
            && self.promotion.content_hash == self.expectation.content_hash
            && Path::new(&self.promotion.storage_path) == self.destination_path;
        if !exact {
            return Err(SkillStoreBoundaryError::Conflict(anyhow::anyhow!(
                "prepared activation destination changed"
            ))
            .into());
        }
        Ok(())
    }

    pub(crate) async fn abort(self) -> anyhow::Result<()> {
        self.store
            .cleanup_failed_promotion_destination(&self.destination)
            .await
    }

    pub(crate) async fn finish(self) {
        if let Err(error) = self.store.cleanup_promoted_source(&self.source).await {
            self.store.record_maintenance_issue(
                &self.record.revision_id,
                "activation_source_cleanup",
                &PathBuf::from(&self.record.storage_path),
                &error,
            );
        }
        let _ = self.destination_path;
    }
}

fn expectation_record<'a>(
    revision_id: &str,
    record: &'a SkillRevisionRecord,
    expectation: &SkillRevisionExpectation,
) -> anyhow::Result<&'a SkillRevisionRecord> {
    if record.revision_id != revision_id
        || SkillRevisionExpectation::from(record) != *expectation
        || expectation.status != crate::skill_state::SkillRevisionStatus::Staging
    {
        return Err(SkillStoreBoundaryError::Conflict(anyhow::anyhow!(
            "activation approval is stale"
        ))
        .into());
    }
    Ok(record)
}

fn is_already_exists(error: &anyhow::Error) -> bool {
    error.chain().any(|cause| {
        let io_error = cause
            .downcast_ref::<std::io::Error>()
            .is_some_and(|error| error.kind() == std::io::ErrorKind::AlreadyExists);
        #[cfg(unix)]
        let native_error = cause
            .downcast_ref::<rustix::io::Errno>()
            .is_some_and(|error| *error == rustix::io::Errno::EXIST);
        #[cfg(not(unix))]
        let native_error = false;
        io_error || native_error
    })
}
