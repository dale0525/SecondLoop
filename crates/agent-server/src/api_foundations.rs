pub struct AppFoundationRuntimes {
    pub memory_tools: Option<agent_runtime::memory_tools::MemoryToolRuntime>,
    pub task_tools: Option<agent_runtime::task_tools::TaskToolRuntime>,
    pub automation_tools: Option<agent_runtime::automation_tools::AutomationToolRuntime>,
    pub attachment_tools: Option<agent_runtime::attachment_tools::AttachmentToolRuntime>,
    pub connector_tools: Option<agent_runtime::connector_tools::ConnectorToolRuntime>,
    pub mail_actions: Option<agent_runtime::foundation_actions::MailActionService>,
}

impl AppFoundationRuntimes {
    pub fn new(
        memory_tools: Option<agent_runtime::memory_tools::MemoryToolRuntime>,
        task_tools: Option<agent_runtime::task_tools::TaskToolRuntime>,
        connector_tools: Option<agent_runtime::connector_tools::ConnectorToolRuntime>,
    ) -> Self {
        Self {
            memory_tools,
            task_tools,
            automation_tools: None,
            attachment_tools: None,
            connector_tools,
            mail_actions: None,
        }
    }

    pub fn with_automation_tools(
        mut self,
        automation_tools: Option<agent_runtime::automation_tools::AutomationToolRuntime>,
    ) -> Self {
        self.automation_tools = automation_tools;
        self
    }

    pub fn with_attachment_tools(
        mut self,
        attachment_tools: Option<agent_runtime::attachment_tools::AttachmentToolRuntime>,
    ) -> Self {
        self.attachment_tools = attachment_tools;
        self
    }

    pub fn with_mail_actions(
        mut self,
        mail_actions: Option<agent_runtime::foundation_actions::MailActionService>,
    ) -> Self {
        self.mail_actions = mail_actions;
        self
    }
}

impl AppState {
    pub(crate) fn mail_actions(
        &self,
    ) -> Option<agent_runtime::foundation_actions::MailActionService> {
        if self.identity_runtime().is_some() {
            return None;
        }
        self.mail_actions.clone()
    }

    pub(crate) fn calendar_actions(
        &self,
    ) -> Option<agent_runtime::calendar_actions::CalendarActionService> {
        if self.identity_runtime().is_some() {
            return None;
        }
        self.calendar_actions.clone()
    }

    pub(crate) fn contacts_actions(
        &self,
    ) -> Option<agent_runtime::contacts_actions::ContactsActionService> {
        if self.identity_runtime().is_some() {
            return None;
        }
        self.contacts_actions.clone()
    }

    pub(crate) fn automation(&self) -> Option<&crate::automation_api::AutomationApiState> {
        self.automation.as_ref()
    }

    pub fn oauth_broker(&self) -> Option<&agent_runtime::oauth::OAuthBroker> {
        self.oauth_broker.as_ref()
    }

    pub(crate) fn mail_account_manager(
        &self,
    ) -> Option<std::sync::Arc<agent_runtime::mail_imap_smtp_accounts::ImapSmtpMailAccountManager>>
    {
        if self.identity_runtime().is_some() {
            return None;
        }
        self.mail_account_manager.clone()
    }

    pub fn with_mail_account_manager(
        mut self,
        manager: std::sync::Arc<agent_runtime::mail_imap_smtp_accounts::ImapSmtpMailAccountManager>,
    ) -> Self {
        self.mail_account_manager = Some(manager);
        self
    }
    pub fn with_mail_foundation(
        mut self,
        connector_tools: agent_runtime::connector_tools::ConnectorToolRuntime,
        mail_actions: agent_runtime::foundation_actions::MailActionService,
    ) -> Self {
        self.connector_tools = Some(connector_tools);
        self.mail_actions = Some(mail_actions);
        self
    }

    pub fn with_calendar_foundation(
        mut self,
        connector_tools: agent_runtime::connector_tools::ConnectorToolRuntime,
        calendar_actions: agent_runtime::calendar_actions::CalendarActionService,
    ) -> Self {
        self.connector_tools = Some(connector_tools);
        self.calendar_actions = Some(calendar_actions);
        self
    }

    pub fn with_contacts_foundation(
        mut self,
        connector_tools: agent_runtime::connector_tools::ConnectorToolRuntime,
        contacts_actions: agent_runtime::contacts_actions::ContactsActionService,
    ) -> Self {
        self.connector_tools = Some(connector_tools);
        self.contacts_actions = Some(contacts_actions);
        self
    }
}
use crate::api::AppState;
