import { AppStatus } from "../hooks/useEchoSyncWS";

interface StatusBarProps {
  status: AppStatus;
  connected: boolean;
}

const STATUS_LABELS: Record<AppStatus, string> = {
  idle: "Ready",
  hearing: "Hearing...",
  transcribing: "Transcribing...",
  extracting: "Extracting...",
  thinking: "Thinking...",
  error: "Error",
};

const STATUS_COLORS: Record<AppStatus, string> = {
  idle: "text-gray-400",
  hearing: "text-green-400",
  transcribing: "text-blue-400",
  extracting: "text-yellow-400",
  thinking: "text-purple-400",
  error: "text-red-400",
};

export function StatusBar({ status, connected }: StatusBarProps) {
  const isHearing = status === "hearing";

  return (
    <div className="flex items-center gap-3 px-4 py-3 bg-gray-900 border-b border-gray-800">
      {/* Microphone indicator with pulse animation */}
      <div className="relative flex items-center justify-center w-8 h-8">
        {isHearing && (
          <>
            <span className="absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-40 animate-ping" />
            <span className="absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-20 animate-ping [animation-delay:0.3s]" />
          </>
        )}
        <span
          className={`relative inline-flex rounded-full w-4 h-4 transition-colors duration-300 ${
            isHearing ? "bg-green-400" : "bg-gray-600"
          }`}
        />
      </div>

      {/* Status label */}
      <span className={`text-sm font-medium transition-colors duration-200 ${STATUS_COLORS[status]}`}>
        {STATUS_LABELS[status]}
      </span>

      {/* Connection indicator */}
      <div className="ml-auto flex items-center gap-1.5">
        <span
          className={`w-2 h-2 rounded-full ${connected ? "bg-green-500" : "bg-red-500"}`}
        />
        <span className="text-xs text-gray-500">
          {connected ? "Connected" : "Disconnected"}
        </span>
      </div>
    </div>
  );
}
