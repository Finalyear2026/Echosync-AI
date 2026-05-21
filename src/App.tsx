import { useEffect, useState } from "react";
import { useEchoSyncWS } from "./hooks/useEchoSyncWS";
import { StatusBar } from "./components/StatusBar";
import { TranscriptPreview } from "./components/TranscriptPreview";
import { HistoryView } from "./components/HistoryView";
import { ModelWizard } from "./components/ModelWizard";

interface ModelStatus {
  models_present: boolean;
  missing: string[];
}

function App() {
  const { status, partialText, isFinal, lastResult, connected } = useEchoSyncWS();
  const [modelStatus, setModelStatus] = useState<ModelStatus | null>(null);
  const [sessionActive, setSessionActive] = useState(false);
  const [activeTab, setActiveTab] = useState<"assistant" | "history">("assistant");

  // Check model status on mount
  useEffect(() => {
    fetch("http://127.0.0.1:8765/models/status")
      .then((r) => r.json())
      .then(setModelStatus)
      .catch(() => setModelStatus({ models_present: true, missing: [] }));
  }, []);

  const [loading, setLoading] = useState(false);

  const toggleSession = async () => {
    if (loading) return;
    setLoading(true);
    const endpoint = sessionActive ? "/session/stop" : "/session/start";
    try {
      const r = await fetch(`http://127.0.0.1:8765${endpoint}`, { method: "POST" });
      const data = await r.json();
      console.log("Session toggle response:", data);
      setSessionActive(!sessionActive);
    } catch (err) {
      console.error("Session toggle error:", err);
      alert("Error: " + err);
    } finally {
      setLoading(false);
    }
  };

  // Show wizard if models missing
  if (modelStatus && !modelStatus.models_present) {
    return (
      <ModelWizard
        missingModels={modelStatus.missing}
        onComplete={() => setModelStatus({ models_present: true, missing: [] })}
      />
    );
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white flex flex-col">
      {/* Status bar */}
      <StatusBar status={status} connected={connected} />

      {/* Main content */}
      <div className="flex-1 flex flex-col max-w-2xl mx-auto w-full px-4 py-6 gap-6">
        {/* App title */}
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight text-white">
            EchoSync AI
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Privacy-first offline voice assistant
          </p>
        </div>

        {/* Transcript preview */}
        <div className="bg-gray-900 rounded-xl border border-gray-800 min-h-[100px]">
          <TranscriptPreview
            partialText={partialText}
            isFinal={isFinal}
            lastResult={lastResult}
          />
        </div>

        {/* Session toggle button */}
        <button
          onClick={toggleSession}
          disabled={!connected || loading}
          className={`w-full py-3 rounded-xl font-semibold text-sm transition-all duration-200 ${
            sessionActive
              ? "bg-red-600 hover:bg-red-500 text-white"
              : "bg-blue-600 hover:bg-blue-500 disabled:bg-gray-800 disabled:text-gray-600 text-white"
          }`}
        >
          {loading ? "Please wait..." : sessionActive ? "Stop Listening" : "Start Listening"}
        </button>

        {/* Tabs */}
        <div className="flex border-b border-gray-800">
          {(["assistant", "history"] as const).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 text-sm font-medium capitalize transition-colors ${
                activeTab === tab
                  ? "text-white border-b-2 border-blue-500"
                  : "text-gray-500 hover:text-gray-300"
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Tab content */}
        {activeTab === "history" && (
          <div className="bg-gray-900 rounded-xl border border-gray-800">
            <HistoryView />
          </div>
        )}

        {activeTab === "assistant" && lastResult && (
          <div className="bg-gray-900 rounded-xl border border-gray-800 px-4 py-3">
            <p className="text-xs text-gray-500 mb-1 font-medium uppercase tracking-wide">
              Response
            </p>
            <p className="text-sm text-gray-200">{lastResult}</p>
          </div>
        )}
      </div>
    </div>
  );
}

export default App;
