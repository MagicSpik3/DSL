import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

DOCX_PATH = Path(__file__).with_name("WAS Round 9 Paper Questionnaire April 2023.docx")
OUT_PATH = Path(__file__).with_name("WAS_Round9_Paper_Questionnaire.yaml")

STOP_WORDS = {
    "All", "Ask", "If", "When", "Which", "The", "This", "What", "How",
    "Code", "Read", "Please", "Enter", "Keep", "And", "Then", "Prompt",
    "Check", "Household", "Individual", "Questionnaire", "Process", "Key",
    "Latest", "Date", "Name", "Known", "Answer", "Sure", "Additional",
    "Routing", "Question", "Wording", "Variable", "Interviewer",
    "Instructions", "Codes", "Response", "Options", "Screen", "Instruction",
    "Own", "Currently", "Rent", "Live", "Allow", "Pause", "Text", "Filter",
    "Names", "Education", "Country", "Housing", "Mortgages", "Value",
    "Equity", "Benefits", "Retirement", "Savings", "Accounts", "Trust",
    "Appendix", "A", "On", "Context", "Reponse", "Interview", "Households",
    "Member", "Members", "Can", "INFORMATION", "Input", "Resident", "Derived",
    "Hhold", "Member", "SURE", "RName"
}


def normalize_text(value):
    return re.sub(r"\s+", " ", value).strip()


def explicit_variable_name(value):
    text = normalize_text(value)
    match = re.search(
        r"Variable name(?:\s*Variable name)*\s*([A-Za-z][A-Za-z0-9]*)",
        text,
        flags=re.IGNORECASE,
    )
    if match:
        return match.group(1)
    return None


def likely_variable_name(value):
    text = normalize_text(value)
    if not text or len(text) > 25:
        return False
    if not re.fullmatch(r"[A-Za-z0-9]+", text):
        return False
    if text in STOP_WORDS:
        return False
    if any(ch.isdigit() for ch in text):
        return True
    if re.search(r"[A-Z][a-z]", text) and re.search(r"[A-Z]", text[1:]):
        return True
    return False


def extract_paragraphs(docx_path):
    with zipfile.ZipFile(docx_path) as zf:
        document_xml = zf.read("word/document.xml")
    root = ET.fromstring(document_xml)
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    paragraphs = []
    for para in root.findall(".//w:p", ns):
        raw = "".join(node.text or "" for node in para.findall(".//w:t", ns))
        cleaned = normalize_text(raw)
        if cleaned:
            paragraphs.append(cleaned)
    return paragraphs


def parse_question_block(block_lines):
    clean_lines = [line for line in block_lines if line and line.lower() not in {"question wording", "variable name", "routing & coding instructions", "interviewer instructions", "pre-codes", "reponse options"}]

    routing = []
    interviewer = []
    question = None
    fills = []
    pre_codes = []

    for line in clean_lines:
        line_norm = normalize_text(line)
        lower = line_norm.lower()
        if lower in {"ask all", "all"}:
            routing.append(line_norm)
            continue
        if line_norm.startswith("[") and line_norm.endswith("]"):
            routing.append(line_norm)
            fills.extend(re.findall(r"\[([^\]]+)\]", line_norm))
            continue
        if "display" in lower or "fill" in lower:
            routing.append(line_norm)
            fills.extend(re.findall(r"\[([^\]]+)\]", line_norm))
            continue
        if lower.startswith("interviewer") or lower.startswith("make sure") or lower.startswith("running prompt") or lower in {"prompt as necessary", "read all response options", "individual prompt", "ask or record", "check", "additional instruction"}:
            interviewer.append(line_norm)
            continue
        if re.match(r"^\d+\.", line_norm):
            match = re.match(r"^(\d+)\.\s*(.*)$", line_norm)
            if match:
                pre_codes.append({"code": int(match.group(1)), "text": match.group(2).strip()})
            continue
        if question is None and any(token in lower for token in ["how do", "what is", "what are", "when did", "which", "is this", "did this", "enter", "please", "do you", "are you"]):
            question = line_norm
            continue
        if question is None and "?" in line_norm:
            question = line_norm
            continue
        if question is None and not lower.startswith("if ") and not lower.startswith("["):
            question = line_norm
            continue
        if lower.startswith("if "):
            interviewer.append(line_norm)
            continue

    response_type = "pre-coded" if pre_codes else None

    return {
        "routing": routing,
        "question": question,
        "text_fills": fills,
        "interviewer_instructions": interviewer,
        "response_type": response_type,
        "pre_codes": pre_codes,
    }


def build_blocks(paragraphs):
    blocks = []
    current = None

    for para in paragraphs:
        explicit = explicit_variable_name(para)
        if explicit:
            if current is not None:
                blocks.append(current)
            current = {"variable": explicit, "lines": []}
            continue

        if current is None and likely_variable_name(para):
            current = {"variable": para, "lines": []}
            continue

        if current is not None:
            if likely_variable_name(para) and not para.lower().startswith("ask") and not para.lower().startswith("if") and para not in {"All", "Ask", "Check"}:
                blocks.append(current)
                current = {"variable": para, "lines": []}
                continue
            current["lines"].append(para)

    if current is not None:
        blocks.append(current)

    return blocks


def yaml_quote(value):
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return '"' + text + '"'


def dump_yaml(questions):
    lines = ["questions:"]
    for entry in questions:
        var = entry.get("variable")
        lines.append(f"  - variable: {yaml_quote(var)}")

        if entry.get("routing"):
            lines.append("    routing:")
            for item in entry["routing"]:
                lines.append(f"      - {yaml_quote(item)}")

        if entry.get("question"):
            lines.append(f"    question: {yaml_quote(entry['question'])}")

        if entry.get("text_fills"):
            lines.append("    text_fills:")
            for item in entry["text_fills"]:
                lines.append(f"      - {yaml_quote(item)}")

        if entry.get("interviewer_instructions"):
            lines.append("    interviewer_instructions:")
            for item in entry["interviewer_instructions"]:
                lines.append(f"      - {yaml_quote(item)}")

        if entry.get("response_type"):
            lines.append(f"    response_type: {yaml_quote(entry['response_type'])}")

        if entry.get("pre_codes"):
            lines.append("    pre_codes:")
            for item in entry["pre_codes"]:
                lines.append(f"      - code: {item['code']}")
                lines.append(f"        text: {yaml_quote(item['text'])}")

    return "\n".join(lines) + "\n"


def main():
    paragraphs = extract_paragraphs(DOCX_PATH)
    blocks = build_blocks(paragraphs)
    questions = []
    for block in blocks:
        parsed = parse_question_block(block["lines"])
        if not parsed["question"] and not parsed["pre_codes"] and not parsed["routing"]:
            continue
        question_entry = {
            "variable": block["variable"],
            "routing": parsed["routing"],
            "question": parsed["question"],
            "text_fills": parsed["text_fills"],
            "interviewer_instructions": parsed["interviewer_instructions"],
            "response_type": parsed["response_type"],
            "pre_codes": parsed["pre_codes"],
        }
        questions.append(question_entry)

    yaml_text = dump_yaml(questions)
    OUT_PATH.write_text(yaml_text, encoding="utf-8")
    print(f"Wrote {len(questions)} question entries to {OUT_PATH}")


if __name__ == "__main__":
    main()
