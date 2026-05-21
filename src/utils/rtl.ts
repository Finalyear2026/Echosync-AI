/**
 * RTL detection utilities for Urdu/Arabic script.
 * Urdu script Unicode range: U+0600–U+06FF
 */

const URDU_ARABIC_RANGE = /[\u0600-\u06FF]/;

/**
 * Returns true if the string contains Urdu/Arabic script characters.
 */
export function containsUrdu(text: string): boolean {
  return URDU_ARABIC_RANGE.test(text);
}

/**
 * Returns the text direction for a given string.
 * "rtl" if Urdu/Arabic characters detected, "ltr" otherwise.
 */
export function getTextDirection(text: string): "rtl" | "ltr" {
  return containsUrdu(text) ? "rtl" : "ltr";
}

/**
 * Split mixed text into segments with their detected direction.
 * Each segment is a run of characters with the same script.
 */
export interface TextSegment {
  text: string;
  dir: "rtl" | "ltr";
}

export function splitByDirection(text: string): TextSegment[] {
  if (!text) return [];

  const segments: TextSegment[] = [];
  let current = "";
  let currentDir: "rtl" | "ltr" = getTextDirection(text[0]);

  for (const char of text) {
    const charDir = URDU_ARABIC_RANGE.test(char) ? "rtl" : "ltr";
    if (charDir === currentDir) {
      current += char;
    } else {
      if (current.trim()) segments.push({ text: current, dir: currentDir });
      current = char;
      currentDir = charDir;
    }
  }

  if (current.trim()) segments.push({ text: current, dir: currentDir });
  return segments;
}
