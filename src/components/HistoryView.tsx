import { useEffect, useState } from "react";
import { getTextDirection } from "../utils/rtl";

interface HistoryRecord {
  id: number;
  transcript: string;
  intent_type: string | null;
  result_summary: string;
  session_at: string;
}

const INTENT_LABELS: Record<string, string> = {
  create_task: "Task Created",
  update_task: "Task Updated",
  complete_task: "Task Completed",
  schedule_meeting: "Meeting Scheduled",
  set_reminder: "Reminder Set",
};

export function HistoryView() {
  const [records, setRecords] = useState<HistoryRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("http://127.0.0.1:8765/history")
      .then((r) => r.json())
      .then((data) => {
        setRecords(data);
        setLoading(false);
      })
      .catch((err) => {
        setError("Could not load history.");
        setLoading(false);
      });
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-32 text-gray-500 text-sm">
        Loading history...
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-32 text-red-400 text-sm">
        {error}
      </div>
    );
  }

  if (records.length === 0) {
    return (
      <div className="flex items-center justify-center h-32 text-gray-600 text-sm italic">
        No voice sessions yet.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2 px-4 py-3 overflow-y-auto max-h-96">
      {records.map((record) => {
        const dir = getTextDirection(record.transcript);
        const label = record.intent_type
          ? INTENT_LABELS[record.intent_type] ?? record.intent_type
          : "Question";
        const time = new Date(record.session_at).toLocaleTimeString([], {
          hour: "2-digit",
          minute: "2-digit",
        });

        return (
          <div
            key={record.id}
            className="bg-gray-800 rounded-lg px-3 py-2 border border-gray-700"
          >
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs text-blue-400 font-medium">{label}</span>
              <span className="text-xs text-gray-500">{time}</span>
            </div>
            <p
              dir={dir}
              className={`text-sm text-gray-300 ${
                dir === "rtl"
                  ? "text-right font-[Noto_Naskh_Arabic,Arial,sans-serif]"
                  : "text-left"
              }`}
            >
              {record.transcript}
            </p>
            {record.result_summary && record.result_summary !== "processed" && (
              <p className="text-xs text-gray-500 mt-1">{record.result_summary}</p>
            )}
          </div>
        );
      })}
    </div>
  );
}
