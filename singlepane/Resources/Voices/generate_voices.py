#!/usr/bin/env python3
"""Generate voice files for all phrases in voices.json using ElevenLabs API."""

import json
import os
import time
import urllib.request
import urllib.error

API_KEY = "sk_8e2ac6108a96f7b5ab9e2042fdffa459d3d5ae2586ddfad8"
MODEL = "eleven_v3"
BASE_URL = "https://api.elevenlabs.io/v1/text-to-speech"

VOICE_IDS = [
    "wFOtYWBAKv6z33WjceQa",
    "WMKg7TxPpPWCryaXE42r",
    "llNlEi50DSCIEuoOIaH7",
    "mKoqwDP2laxTdq1gEgU6",
    "Bj9UqZbhQsanLzgalpEG",
    "RDSy0QN68yhrjuOgqzQ4",
    "NXaTw4ifg0LAguvKuIwZ",
    "BBfN7Spa3cqLPH1xAS22",
    "CKfuQaJKfvUG2Wtrda3Y",
]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VOICES_JSON = os.path.join(SCRIPT_DIR, "voices.json")


def get_char_count(text):
    """Return character count for a phrase (ElevenLabs bills per character)."""
    return len(text)


def generate_speech(voice_id, text, output_path):
    """Call ElevenLabs TTS API and save the MP3 file."""
    url = f"{BASE_URL}/{voice_id}"
    payload = json.dumps({
        "text": text,
        "model_id": MODEL,
        "voice_settings": {
            "stability": 0.75,
            "similarity_boost": 0.75,
            "style": 0.0,
            "use_speaker_boost": True,
        },
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("xi-api-key", API_KEY)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "audio/mpeg")

    try:
        with urllib.request.urlopen(req) as resp:
            with open(output_path, "wb") as f:
                f.write(resp.read())
        return True
    except urllib.error.HTTPError as e:
        print(f"    ERROR {e.code}: {e.read().decode()}")
        return False


def main():
    with open(VOICES_JSON, "r") as f:
        phrases = json.load(f)

    total_phrases = sum(len(v) for v in phrases.values())
    total_voices = len(VOICE_IDS)
    total_calls = total_phrases * total_voices

    # Pre-calculate total characters across all voices
    chars_per_voice = sum(len(text) for lines in phrases.values() for text in lines)
    total_chars = chars_per_voice * total_voices

    print(f"{'='*60}")
    print(f"  ElevenLabs Voice Generator")
    print(f"  {total_voices} voices x {total_phrases} phrases = {total_calls} files")
    print(f"  Estimated total characters: {total_chars:,}")
    print(f"{'='*60}")
    print()

    completed = 0
    failed = 0
    chars_used = 0

    for voice_idx, voice_id in enumerate(VOICE_IDS, start=1):
        voice_dir = os.path.join(SCRIPT_DIR, voice_id)
        file_num = 0

        print(f"{'─'*60}")
        print(f"  Voice {voice_idx}/{total_voices}: {voice_id}")
        print(f"{'─'*60}")

        for category, lines in phrases.items():
            category_dir = os.path.join(voice_dir, category)
            os.makedirs(category_dir, exist_ok=True)

            for i, text in enumerate(lines, start=1):
                file_num += 1
                filename = f"{category}_{i:02d}.mp3"
                output_path = os.path.join(category_dir, filename)
                char_count = get_char_count(text)

                if os.path.exists(output_path):
                    chars_used += char_count
                    completed += 1
                    print(f"  SKIP  voice {voice_idx}/{total_voices}, file {file_num}/{total_phrases}  |  {category}/{filename}  (exists)")
                    continue

                success = generate_speech(voice_id, text, output_path)

                if success:
                    completed += 1
                    chars_used += char_count
                else:
                    failed += 1
                    time.sleep(2)

                print(f"  voice {voice_idx}/{total_voices}, file {file_num}/{total_phrases}  |  {category}/{filename}  |  \"{text}\"  |  credits: {chars_used:,} chars")

                # Small delay to respect rate limits
                time.sleep(0.3)

        print()
        print(f"  Voice {voice_idx} complete. Running totals: {completed} ok, {failed} failed, {chars_used:,} chars used")
        print()

    print(f"{'='*60}")
    print(f"  FINISHED")
    print(f"  Generated: {completed}")
    print(f"  Failed:    {failed}")
    print(f"  Total characters used: {chars_used:,}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
