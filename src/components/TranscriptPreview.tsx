import { useEffect, useRef } from "react";
import { splitByDirection, getTextDirection } from "../utils/rtl";

interface TranscriptPreviewProps {
  partialText: string;
  isFinal: boolean;
  lastResult: string;
}

export function TranscriptPreview({
  partialText,
  isFinal,
  lastResult,
}: TranscriptPreviewProps) {
  const prevFinalRef = useRef(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Animate transition when partial becomes final
  useEffect(() => {
    if (isFinal && !prevFinalRef.current && containerRef.current) {
      containerRef.current.classList.add("opacity-50");
      setTimeout(() => {
        containerRef.current?.classList.remove("opacity-50");
      }, 300);
    }
    prevFinalRef.current = isFinal;
  }, [isFinal]);

  const displayText = partialText || lastResult;
  if (!displayText) {
    return (
      <div className="flex items-center justify-center h-24 text-gray-600 text-sm italic">
        Speak to begin...
      </div>
    );
  }

  const segments = splitByDirection(displayText);
  const overallDir = getTextDirection(displayText);

  return (
    <div
      ref={containerRef}
      className="transition-opacity duration-300 px-4 py-3"
    >
      {/* Partial indicator */}
      {partialText && !isFinal && (
        <div className="flex items-center gap-1.5 mb-2">
          <span className="w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse" />
          <span className="text-xs text-blue-400 font-medium">Listening...</span>
        </div>
      )}

      {/* Transcript text with per-segment RTL detection */}
      <div
        dir={overallDir}
        className={`text-base leading-relaxed ${
          isFinal ? "text-white" : "text-gray-300"
        } ${
          overallDir === "rtl"
            ? "font-[Noto_Naskh_Arabic,Arial,sans-serif] text-right"
            : "font-sans text-left"
        }`}
      >
        {segments.length > 1
          ? segments.map((seg, i) => (
              <span
                key={i}
                dir={seg.dir}
                className={
                  seg.dir === "rtl"
                    ? "font-[Noto_Naskh_Arabic,Arial,sans-serif]"
                    : "font-sans"
                }
              >
                {seg.text}
              </span>
            ))
          : displayText}
      </div>

      {/* Final indicator */}
      {isFinal && partialText && (
        <div className="mt-1 text-xs text-green-500">✓ Finalized</div>
      )}
    </div>
  );
}
