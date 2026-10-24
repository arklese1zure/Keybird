#Requires AutoHotkey v2.0

;		=========================================================================
;		|||||				Keybird - Markdown -> RTF					|||||
;		=========================================================================
; Converts a constrained, self-authored subset of Markdown into RTF suitable for
; RichEdit.SetText(). No dependencies beyond AHK v2 built-ins.
;
; Supported: headers (# .. ######), bold, italic, strikethrough, inline code,
; fenced code blocks, blockquotes, ordered/unordered lists (2-space nesting),
; horizontal rules, links, and tables.
;
; NOT supported: images, footnotes, nested emphasis inside link labels,
; markdown escape sequences (\* for a literal asterisk, etc).
;
; Tables render as plain monospaced, padded text (like a code block) rather
; than real RTF tables (\trowd/\cellx column math) - much simpler, and reads
; just as cleanly since the whole point of markdown's table syntax is already
; being readable as plain text. Cell content DOES support the same inline
; formatting as everywhere else (bold, italic, strikethrough, inline code,
; links) - column widths are computed from each cell's rendered width, not
; its raw markdown source, so alignment holds regardless of markup. Alignment
; hints (:---:, ---:) are still ignored - everything left-aligns.
;
; Links: [label](url) renders as "label (url)", with the bare url left as
; plain text for the RichEdit control's own AutoURL detector to pick up as a
; clickable link (RE.AutoURL(True), same mechanism RichEditSample.ahk uses).
; An earlier version rendered these as RTF hyperlink fields so the doc could
; show a clean label with the URL hidden behind it, but reading a clicked
; field's real href back out of a RichEdit control requires COM
; (ITextDocument) that this project's RichEdit.ahk wrapper doesn't expose, so
; that approach was dropped in favor of this less elegant but much less
; fragile one.

MarkdownToRTF(md) {
	bt := Chr(96) ; backtick - built via Chr() rather than embedded literally,
	              ; since AHK's own backtick-escaping rules make raw backticks
	              ; inside string/regex literals easy to get subtly wrong.
	fence := bt bt bt

	; Font table: f0 = body (Segoe UI), f1 = monospace (Consolas).
	; Color table: 1 = body text (black), 2 = blockquote text (gray),
	;              3 = link text (blue), 4 = code background (near-white).
	; Index 0 is intentionally empty -> RTF's "auto/none" color.
	rtf := "{\rtf1\ansi\ansicpg1252\deff0"
		. "{\fonttbl{\f0\fswiss Segoe UI;}{\f1\fmodern Consolas;}}"
		. "{\colortbl;\red0\green0\blue0;\red100\green100\blue100;\red0\green102\blue204;\red245\green245\blue245;}"
		. "\f0\fs22\cf1`n"

	body := ""
	inCodeBlock := false
	codeBuffer := ""
	inTable := false
	tableJustStarted := false
	tableRows := []

	lines := StrSplit(md, "`n", "`r")
	; Trailing blank lines (near-universal - most files end with a newline,
	; which StrSplit turns into one or more empty trailing entries) shouldn't
	; render as a stray gap at the bottom now that blank lines are visible.
	while (lines.Length && Trim(lines[lines.Length]) = "")
		lines.Pop()
	for idx, line in lines {
		; --- Fenced code blocks -------------------------------------------
		if (SubStr(Trim(line), 1, 3) = fence) {
			if !inCodeBlock {
				inCodeBlock := true
				codeBuffer := ""
			} else {
				inCodeBlock := false
				body .= RenderCodeBlock(codeBuffer)
			}
			continue
		}
		if inCodeBlock {
			codeBuffer .= line "`n"
			continue
		}

		; --- Table continuation/close ---------------------------------------
		; (Table start is detected further below, alongside the other line
		; types, since it needs to run after the fenced-code-block checks
		; above but shares the same "what kind of line is this" chain below.)
		if inTable {
			if tableJustStarted {
				; This line is the "|---|---|" delimiter row that confirmed
				; the table - it carries no content of its own, just consume it.
				tableJustStarted := false
				continue
			}
			if InStr(line, "|") && Trim(line) != "" {
				tableRows.Push(ParseTableRow(line))
				continue
			}
			; Anything else ends the table - flush it, then let this same
			; line fall through to the normal per-line-type checks below,
			; since it's not part of the table.
			body .= RenderTable(tableRows)
			inTable := false
			tableRows := []
		}

		; --- Blank line: renders as one line-height of empty space. A run of
		; several consecutive blank lines in the source gives proportionally
		; more space, since each is handled independently - this is what
		; makes it usable as a manual spacing tool.
		if Trim(line) = "" {
			body .= "\pard\li0\f0\fs22\cf1\par`n"
			continue
		}

		; --- Table start ------------------------------------------------------
		; A line containing "|" immediately followed by a "|---|---|"-style
		; delimiter row is the start of a table.
		if InStr(line, "|") && idx < lines.Length && IsTableDelimiterRow(lines[idx + 1]) {
			tableRows := [ParseTableRow(line)]
			inTable := true
			tableJustStarted := true
			continue
		}

		; --- Horizontal rule --------------------------------------------------
		if RegExMatch(line, "^\s*(-{3,}|\*{3,}|_{3,})\s*$") {
			hrRtf := ""
			loop 40
				hrRtf .= "\u9472?" ; U+2500 box-drawing horizontal line
			body .= "\pard\li0\fs16\cf2 " hrRtf "\fs22\cf1\par`n"
			continue
		}

		; --- Headers ------------------------------------------------------
		if RegExMatch(line, "^(#{1,6})\s+(.*)$", &m) {
			static headerSizes := Map(1, 36, 2, 32, 3, 28, 4, 24, 5, 22, 6, 22)
			fs := headerSizes[StrLen(m[1])]
			; Space before/after scaled to the header's own size (before ~=
			; its point size, after ~= half that) so bigger headers get
			; proportionally more breathing room. \pard resets sb/sa back to
			; 0 for whatever paragraph type comes next, same as it already
			; does for \li - nothing needs an explicit reset on the other end.
			sb := fs * 10, sa := fs * 5
			body .= "\pard\li0\sb" sb "\sa" sa "\b\fs" fs " " InlineToRTF(m[2]) "\b0\fs22\par`n"
			continue
		}

		; --- Blockquote -----------------------------------------------------
		if RegExMatch(line, "^\s*>\s?(.*)$", &m) {
			body .= "\pard\li720\i\cf2 " InlineToRTF(m[1]) "\i0\cf1\par`n"
			continue
		}

		; --- Unordered list (2 spaces = one nesting level) -------------------
		if RegExMatch(line, "^(\s*)([-*+])\s+(.*)$", &m) {
			level := Floor(StrLen(m[1]) / 2) + 1
			body .= "\pard\li" (360 * level) "\fi-240 \u8226? \tab " InlineToRTF(m[3]) "\par`n"
			continue
		}

		; --- Ordered list -----------------------------------------------------
		if RegExMatch(line, "^(\s*)(\d+)\.\s+(.*)$", &m) {
			level := Floor(StrLen(m[1]) / 2) + 1
			body .= "\pard\li" (360 * level) "\fi-240 " m[2] ".\tab " InlineToRTF(m[3]) "\par`n"
			continue
		}

		; --- Default: plain paragraph -----------------------------------------
		body .= "\pard\li0 " InlineToRTF(line) "\par`n"
	}

	; If a doc forgets to close its last fence, flush whatever was buffered
	; rather than silently dropping it. Same idea for a table that runs to
	; the very last line with no trailing blank line after it.
	if inCodeBlock
		body .= RenderCodeBlock(codeBuffer)
	if inTable
		body .= RenderTable(tableRows)

	return rtf body "}"
}

; -------------------------------------------------------------------------------
RenderCodeBlock(code) {
	code := RTrim(code, "`n")
	out := ""
	for _, line in StrSplit(code, "`n", "`r")
		out .= "\pard\li360\highlight4\f1\fs20 " RtfEscapeText(line) "\highlight0\f0\fs22\par`n"
	return out
}

; -------------------------------------------------------------------------------
IsTableDelimiterRow(line) {
	t := Trim(line)
	; A delimiter row is made up of nothing but whitespace, pipes, colons and
	; dashes (e.g. "| --- | :---: | ---: |"), and needs at least one of each
	; of the last two to tell it apart from a blank line or an hr.
	return InStr(t, "-") && InStr(t, "|") && RegExMatch(t, "^[\s\|:\-]+$")
}

; -------------------------------------------------------------------------------
ParseTableRow(line) {
	t := Trim(line)
	; Strip one leading/trailing pipe if present, so "| a | b |" and "a | b"
	; both split into the same two cells.
	if (SubStr(t, 1, 1) = "|")
		t := SubStr(t, 2)
	if (SubStr(t, -1) = "|")
		t := SubStr(t, 1, StrLen(t) - 1)
	cells := []
	for _, cell in StrSplit(t, "|")
		cells.Push(Trim(cell))
	return cells
}

; -------------------------------------------------------------------------------
RenderTable(rows) {
	if !rows.Length
		return ""

	; Rows may have inconsistent cell counts if the source doc is a little
	; sloppy - work out the widest row and pad the rest out to match rather
	; than throwing away misaligned data.
	numCols := 0
	for _, row in rows
		numCols := Max(numCols, row.Length)

	; Widths come from each cell's RENDERED length (markdown stripped away),
	; not its raw source length - **bold** is 4 characters shorter on screen
	; than in the markdown, and padding against the wrong number misaligns
	; the whole column the moment any cell in it uses formatting.
	widths := []
	loop numCols
		widths.Push(3) ; floor width, so the separator line under short columns is still visible

	for _, row in rows
		loop numCols {
			cell := (A_Index <= row.Length) ? row[A_Index] : ""
			widths[A_Index] := Max(widths[A_Index], MarkdownVisibleWidth(cell))
		}

	out := ""
	for rowIdx, row in rows {
		bold := (rowIdx = 1) ; header row - bolded as a whole, on top of whatever
		                     ; formatting the cell's own markdown adds
		lineRtf := "\pard\li360\highlight4\f1\fs20 "
		loop numCols {
			cell := (A_Index <= row.Length) ? row[A_Index] : ""
			if (A_Index > 1)
				lineRtf .= " | "
			if bold
				lineRtf .= "\b "
			lineRtf .= InlineToRTF(cell)
			if bold
				lineRtf .= "\b0 "
			; Pad with plain spaces to the column's rendered width. InlineToRTF's
			; own {}-wrapped groups are already closed by this point, so these
			; spaces sit safely outside any formatting they'd otherwise inherit.
			loop (widths[A_Index] - MarkdownVisibleWidth(cell))
				lineRtf .= " "
		}
		out .= lineRtf "\highlight0\f0\fs22\par`n"

		; Separator line right under the header, built from the same widths
		; rather than copied from the source, so it always lines up.
		if (rowIdx = 1) {
			sepText := ""
			loop numCols {
				dashes := ""
				loop widths[A_Index]
					dashes .= "-"
				sepText .= (A_Index > 1 ? "-+-" : "") . dashes
			}
			out .= "\pard\li360\highlight4\f1\fs20 " sepText "\highlight0\f0\fs22\par`n"
		}
	}
	return out
}

; -------------------------------------------------------------------------------
MarkdownVisibleWidth(text) {
	; Mirrors InlineToRTF's own transformations on plain text instead of
	; generating RTF, purely to get an accurate character count for table
	; column widths - padding against the raw markdown source (still full of
	; **, _, [...](...) etc) would misalign columns the moment that markup
	; actually renders away.
	; Known gap: unlike InlineToRTF, this doesn't shield code-span content
	; from the bold/italic/strike passes below, so a cell with literal
	; markdown-looking characters INSIDE a `code span` could be undercounted
	; by a character or two. Not expected to come up in practice for
	; reference-table content.
	t := text
	t := RegExReplace(t, "\[([^\]]+)\]\(([^)\s]+)\)", "$1 ($2)")
	bt := Chr(96)
	codePattern := bt "([^" bt "]+?)" bt
	t := RegExReplace(t, codePattern, "$1")
	t := RegExReplace(t, "\*\*(.+?)\*\*", "$1")
	t := RegExReplace(t, "__(.+?)__", "$1")
	t := RegExReplace(t, "\*(.+?)\*", "$1")
	t := RegExReplace(t, "_(.+?)_", "$1")
	t := RegExReplace(t, "~~(.+?)~~", "$1")
	return StrLen(t)
}

; -------------------------------------------------------------------------------
InlineToRTF(text) {
	text := RtfEscapeText(text)
	bt := Chr(96)

	; Inline code spans are pulled out first so nothing inside them (*, _, [, ])
	; gets reinterpreted as further markdown syntax. Extracted spans are swapped
	; for Private-Use-Area placeholder characters (never appear in real text)
	; and restored after every other substitution below has run.
	codeSpans := []
	pos := 1, out := ""
	codePattern := bt "([^" bt "]+?)" bt
	while (found := RegExMatch(text, codePattern, &m, pos)) {
		out .= SubStr(text, pos, found - pos)
		codeSpans.Push(m[1])
		out .= Chr(0xE000 + codeSpans.Length)
		pos := found + StrLen(m[0])
	}
	text := out . SubStr(text, pos)

	; Links: [label](url) - extracted the same way as code spans (so bold/
	; italic markers inside a URL, if any, don't get misread), restored last
	; as plain "label (url)" text.
	linkSpans := []
	pos := 1, out := ""
	while (found := RegExMatch(text, "\[([^\]]+)\]\(([^)\s]+)\)", &m, pos)) {
		out .= SubStr(text, pos, found - pos)
		linkSpans.Push({label: m[1], url: m[2]})
		out .= Chr(0xE100 + linkSpans.Length)
		pos := found + StrLen(m[0])
	}
	text := out . SubStr(text, pos)

	; Bold / italic / strikethrough. Order matters: ** before * so a bold span
	; doesn't get read as two adjacent italic markers first.
	text := RegExReplace(text, "\*\*(.+?)\*\*", "{\b $1}")
	text := RegExReplace(text, "__(.+?)__", "{\b $1}")
	text := RegExReplace(text, "\*(.+?)\*", "{\i $1}")
	text := RegExReplace(text, "_(.+?)_", "{\i $1}")
	text := RegExReplace(text, "~~(.+?)~~", "{\strike $1}")

	; Restore links as plain "label (url)" text. The url is left bare and
	; word-bounded so RE.AutoURL(True) can detect and mark it clickable on
	; its own - the click handler then just reads back the clicked range's
	; text directly, exactly as RichEditSample.ahk's RE2_Link does.
	for i, link in linkSpans
		text := StrReplace(text, Chr(0xE100 + i), link.label " (" link.url ")")

	; Restore inline code spans in the monospace font with a light background.
	for i, code in codeSpans
		text := StrReplace(text, Chr(0xE000 + i), "{\f1\highlight4 " code "}")

	return text
}

; -------------------------------------------------------------------------------
RtfEscapeText(text) {
	; RTF metacharacters must be escaped before anything else touches the
	; string, since every markdown substitution above inserts real RTF control
	; words that must NOT be escaped a second time.
	text := StrReplace(text, "\", "\\")
	text := StrReplace(text, "{", "\{")
	text := StrReplace(text, "}", "\}")

	; Anything outside Latin-1 needs an explicit \u escape - RichEdit.SetText()
	; only auto-converts the whole string to the system ANSI codepage, which
	; silently mangles anything that codepage can't represent (box-drawing
	; characters, curly quotes, non-Latin scripts...). Common accented Latin-1
	; letters (á, é, ñ, ¿...) pass straight through the codepage fine and don't
	; need escaping.
	out := ""
	loop Parse text {
		code := Ord(A_LoopField)
		if (code > 255) {
			if (code > 32767)
				code -= 65536
			out .= "\u" code "?"
		} else {
			out .= A_LoopField
		}
	}
	return out
}
