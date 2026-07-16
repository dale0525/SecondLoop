import { Copy } from "lucide-react";
import Markdown from "react-markdown";
import rehypeKatex from "rehype-katex";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import "katex/dist/katex.min.css";

import type { StructuredContent } from "../../runtimeEvents";
import type {
  MessageAttachment,
  StructuredContentActionHandler,
} from "../../types";
import { AttachmentChip, MediaFileChip } from "./AttachmentChip";
import {
  describeMediaSrc,
  splitMediaSegments,
  MediaToken
} from "./mediaSegments";
import { StructuredContentView } from "./StructuredContentView";

type MessageContentProps = {
  attachments?: MessageAttachment[];
  body: string;
  isStreaming?: boolean;
  onStructuredContentAction?: StructuredContentActionHandler;
  role: "assistant" | "user";
  structuredContent?: StructuredContent;
};

type CodeProps = {
  children?: React.ReactNode;
  className?: string;
};

function isInlineCode(children: React.ReactNode, className?: string): boolean {
  return !className && typeof children === "string" && !children.includes("\n");
}

function CodeBlock({ children, className }: CodeProps): JSX.Element {
  if (isInlineCode(children, className)) {
    return <code>{children}</code>;
  }

  const code = String(children ?? "").replace(/\n$/, "");
  const language = /language-([A-Za-z0-9_-]+)/.exec(className ?? "")?.[1] ?? "code";

  return (
    <div className="chat-code-block">
      <div className="chat-code-header">
        <span className="chat-code-lang">{language}</span>
        <button
          aria-label="Copy code"
          className="chat-code-copy"
          onClick={() => void navigator.clipboard?.writeText(code)}
          type="button"
        >
          <Copy size={13} aria-hidden="true" />
        </button>
      </div>
      <pre>
        <code>{code}</code>
      </pre>
    </div>
  );
}

function MediaPreview({ token }: { token: MediaToken }): JSX.Element {
  const canPreviewImage =
    token.isImage &&
    (token.src.startsWith("data:image/") || /^https?:\/\//i.test(token.src));

  if (!canPreviewImage) {
    return <MediaFileChip token={token} />;
  }

  return (
    <figure className="chat-media-preview">
      <img src={token.src} alt={token.name} />
      <figcaption>{token.name}</figcaption>
    </figure>
  );
}

function MarkdownContent({ children }: { children: string }): JSX.Element {
  return (
    <Markdown
      remarkPlugins={[remarkGfm, remarkMath]}
      rehypePlugins={[rehypeKatex]}
      components={{
        a: ({ children, href }) => (
          <a href={href} rel="noreferrer" target="_blank">
            {children}
          </a>
        ),
        code: ({ children, className }) => (
          <CodeBlock className={className}>{children}</CodeBlock>
        ),
        pre: ({ children }) => <>{children}</>,
        table: ({ children }) => (
          <div className="chat-table-scroll">
            <table>{children}</table>
          </div>
        ),
        img: ({ alt, src }) => {
          if (!src) return null;
          const token = describeMediaSrc(src);
          return token.isImage ? (
            <MediaPreview token={{ ...token, name: alt || token.name }} />
          ) : (
            <MediaFileChip token={token} />
          );
        }
      }}
    >
      {children}
    </Markdown>
  );
}

export function MessageContent({
  attachments,
  body,
  isStreaming = false,
  onStructuredContentAction,
  role,
  structuredContent,
}: MessageContentProps): JSX.Element {
  if (structuredContent) {
    return (
      <StructuredContentView
        content={structuredContent}
        onAction={onStructuredContentAction}
      />
    );
  }
  const segments =
    role === "assistant" ? splitMediaSegments(body) : [{ start: 0, type: "text" as const, value: body }];

  return (
    <>
      {attachments && attachments.length > 0 ? (
        <div className="chat-attachment-row" aria-label="Message attachments">
          {attachments.map((attachment) => (
            <AttachmentChip attachment={attachment} key={attachment.id} />
          ))}
        </div>
      ) : null}
      <div className="message-content">
        {segments.map((segment) =>
          segment.type === "text" ? (
            segment.value.trim() ? (
              <MarkdownContent key={`text-${segment.start}`}>
                {segment.value}
              </MarkdownContent>
            ) : null
          ) : (
            <MediaPreview key={`media-${segment.start}`} token={segment.token} />
          )
        )}
        {isStreaming ? (
          <span className="message-streaming-cursor" aria-hidden="true" />
        ) : null}
      </div>
    </>
  );
}
