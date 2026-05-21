import { useState, useEffect } from "react";

interface ModelWizardProps {
  missingModels: string[];
  onComplete: () => void;
}

interface DownloadProgress {
  filename: string;
  progress: number;
  done: boolean;
  error: string | null;
}

export function ModelWizard({ missingModels, onComplete }: ModelWizardProps) {
  const [sourcePath, setSourcePath] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [downloads, setDownloads] = useState<Record<string, DownloadProgress>>({});
  const [ws, setWs] = useState<WebSocket | null>(null);

  useEffect(() => {
    const socket = new WebSocket("ws://127.0.0.1:8765/ws/status");
    socket.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.event === "download_progress") {
          setDownloads((prev) => ({
            ...prev,
            [msg.filename]: {
              filename: msg.filename,
              progress: msg.progress,
              done: false,
              error: null,
            },
          }));
        } else if (msg.event === "download_complete") {
          setDownloads((prev) => ({
            ...prev,
            [msg.filename]: {
              filename: msg.filename,
              progress: msg.success ? 100 : prev[msg.filename]?.progress ?? 0,
              done: msg.success,
              error: msg.success ? null : msg.message,
            },
          }));
        }
      } catch {
        // ignore
      }
    };
    setWs(socket);
    return () => socket.close();
  }, []);

  // Check if all downloads complete
  useEffect(() => {
    if (confirmed && missingModels.length > 0) {
      const allDone = missingModels.every((m) => downloads[m]?.done);
      if (allDone) {
        setTimeout(onComplete, 1000);
      }
    }
  }, [downloads, confirmed, missingModels, onComplete]);

  const handleConfirm = async () => {
    if (!sourcePath.trim()) return;
    setConfirmed(true);

    for (const filename of missingModels) {
      const url = sourcePath.endsWith("/")
        ? `${sourcePath}${filename}`
        : `${sourcePath}/${filename}`;

      await fetch("http://127.0.0.1:8765/models/download", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ source_url: url, filename }),
      });
    }
  };

  return (
    <div className="fixed inset-0 bg-gray-950 flex items-center justify-center z-50">
      <div className="bg-gray-900 border border-gray-700 rounded-xl p-8 w-full max-w-lg shadow-2xl">
        <h2 className="text-xl font-semibold text-white mb-2">
          First-Run Setup
        </h2>
        <p className="text-gray-400 text-sm mb-6">
          EchoSync needs AI model files to work. Please provide the path or URL
          to your model directory.
        </p>

        <div className="mb-4">
          <p className="text-xs text-gray-500 mb-2 font-medium uppercase tracking-wide">
            Missing models
          </p>
          <ul className="space-y-1">
            {missingModels.map((m) => (
              <li key={m} className="text-sm text-gray-300 flex items-center gap-2">
                <span className="w-1.5 h-1.5 rounded-full bg-yellow-400" />
                {m}
              </li>
            ))}
          </ul>
        </div>

        {!confirmed ? (
          <>
            <label className="block text-sm text-gray-400 mb-1">
              Model source path or URL
            </label>
            <input
              type="text"
              value={sourcePath}
              onChange={(e) => setSourcePath(e.target.value)}
              placeholder="C:\models\ or https://your-mirror.com/models/"
              className="w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-blue-500 mb-4"
            />
            <button
              onClick={handleConfirm}
              disabled={!sourcePath.trim()}
              className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 disabled:text-gray-500 text-white font-medium py-2 rounded-lg transition-colors"
            >
              Download Models
            </button>
          </>
        ) : (
          <div className="space-y-4">
            {missingModels.map((filename) => {
              const dl = downloads[filename];
              const progress = dl?.progress ?? 0;
              const done = dl?.done ?? false;
              const error = dl?.error ?? null;

              return (
                <div key={filename}>
                  <div className="flex justify-between text-xs text-gray-400 mb-1">
                    <span>{filename}</span>
                    <span>
                      {error
                        ? "Failed"
                        : done
                        ? "Complete"
                        : `${progress.toFixed(0)}%`}
                    </span>
                  </div>
                  <div className="w-full bg-gray-700 rounded-full h-1.5">
                    <div
                      className={`h-1.5 rounded-full transition-all duration-300 ${
                        error
                          ? "bg-red-500"
                          : done
                          ? "bg-green-500"
                          : "bg-blue-500"
                      }`}
                      style={{ width: `${progress}%` }}
                    />
                  </div>
                  {error && (
                    <p className="text-xs text-red-400 mt-1">{error}</p>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
