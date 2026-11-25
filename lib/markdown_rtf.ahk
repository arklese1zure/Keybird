#Requires AutoHotkey v2.0

;		=========================================================================
;		|||||				Keybird - Markdown -> RTF					|||||
;		=========================================================================
; Converts Markdown into RTF suitable for RichEdit.SetText(). No dependencies
; beyond AHK v2 built-ins (plus Crypt32.dll, for the hex encoding of images).
; Public entry point: MarkdownToRTF(md, hardBreaks := false, opts := "").
;
; Pipeline (v2 of this file):
;   1. MdParseBlocks  - line-oriented block parser: paragraphs (soft-wrapped
;                       lines are joined), ATX and setext headings, fenced and
;                       indented code, nested blockquotes, nested bullet and
;                       numbered lists (with continuation lines and task
;                       boxes), horizontal rules, tables, reference-link
;                       definitions.
;   2. MdInlineNodes  - inline parser: backslash escapes, code spans of any
;                       backtick length, links ([a](u), [a][ref], [a], <url>),
;                       images (embedded, or an "[Image ...]" note), CommonMark-style
;                       emphasis (** __ * _ ~~ with left/right-flanking rules,
;                       so snake_case_names and "2 * 3 * 4" stay literal) and
;                       the inline HTML tags <br> <u> <ins> <sup> <sub> <b>
;                       <strong> <i> <em> <s> <del> <strike>.
;   3. MdRenderBlock  - RTF writer. Spacing between blocks comes from RTF
;                       space-before/after, NOT from blank paragraphs: blank
;                       lines in the Markdown only separate blocks.
;
; Links: [label](url) renders as "label (url)", with the bare url left as
; plain text for the RichEdit control's own AutoURL detector to pick up as a
; clickable link (RE.AutoURL(True)). Reading a clicked RTF hyperlink field's
; real href back out of a RichEdit control needs COM (ITextDocument) that this
; project's RichEdit.ahk wrapper doesn't expose, so that approach stays
; dropped. Links to "#anchors" show only their label.
;
; Tables render as monospaced, padded plain text (like a code block) with
; column widths computed from each cell's RENDERED text, honoring the
; :--- / :---: / ---: alignment hints.
;
; Every non-ASCII character is written as an RTF \uN? escape, so the output
; is pure 7-bit text and cannot be mangled by the machine's ANSI codepage
; (Keybird runs from USB on whatever Windows it finds).
;
; Obsidian niceties: "> [!type] Title" callouts (title shown in bold), [[wiki
; links]] (shown as their alias or target), ![[image.png]] / ![[image.png|300]]
; embeds, and ![alt|300](image.png) width hints. A ![[note]] embed of a
; non-image shows as "[Embed: note]".
;
; Images: PNG and JPEG files (the format is detected from the file's header, not
; its extension) are decoded with GDI+ and embedded as 24-bit \dibitmap0
; pictures, transparency flattened onto white: RichEdit (Msftedit) does not draw
; \pngblip / \jpegblip pictures. They are scaled down - never up - to
; opts.maxWidth, keeping the aspect ratio. Pass an options object to turn this on:
;
;     MarkdownToRTF(md, false, {baseDir: "C:\kb\docs"        ; REQUIRED for images: relative paths start here
;                              , maxWidth: 8000              ; twips (1440 = 1 inch); default 8000
;                              , imageDirs: ["C:\kb\attach"] ; extra folders searched for a bare file name
;                              , maxBytes: 4194304           ; larger files are not embedded; default 4 MB
;                              , warn: (msg) => Log(msg)     ; optional: told why an image was not shown
;                              , dpi: 96                     ; bitmap pixels per inch; default A_ScreenDPI
;                              , maxPixels: 40000000         ; bigger source images (w x h) are not decoded; default 40 MP
;                              , maxTotalBytes: 8388608})    ; picture data per document; default 8 MB
;
; Without baseDir nothing is read from disk and every image is shown as
; "[Image: alt]". Remote (http/https) images are never downloaded; they show
; as "[Image: alt (url)]". An image that cannot be shown always leaves a visible
; italic note saying why: "[Image missing: x]", "[Image format not supported:
; x]" (GIF, BMP, SVG, WebP...), "[Image too large: x]", "[Image could not be
; loaded: x]" or "[Image not shown, too many pictures on this page: x]" - it
; never silently disappears. Images inside table cells stay
; as "[Image: alt]" notes, because tables are monospaced text.
;
; Not supported: footnotes, HTML blocks (unknown tags are shown as literal
; text), setext/ATX headings inside list items.
;
; -----------------------------------------------------------------------------
; The block/inline parsing design (CommonMark-style block structure and the
; delimiter-run emphasis algorithm) is ported from AhkWord's rte_markdown6.cs:
;
;   AhkWord - https://github.com/burque505/AhkWord
;   MIT License
;   Copyright (c) 2026 burque505
;
;   Permission is hereby granted, free of charge, to any person obtaining a
;   copy of this software and associated documentation files (the "Software"),
;   to deal in the Software without restriction, including without limitation
;   the rights to use, copy, modify, merge, publish, distribute, sublicense,
;   and/or sell copies of the Software, and to permit persons to whom the
;   Software is furnished to do so, subject to the following conditions:
;
;   The above copyright notice and this permission notice shall be included in
;   all copies or substantial portions of the Software.
;
;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;   DEALINGS IN THE SOFTWARE.
; -----------------------------------------------------------------------------
;
; Implementation notes:
;  - No top-level (auto-execute) state: constants live in static locals so
;    this file works no matter where it is #Include-d.
;  - All internal helpers are prefixed "Md". RtfEscapeText keeps its old name.
;  - Style flags on inline nodes: 1 bold, 2 italic, 4 strike, 8 code,
;    16 underline, 32 superscript, 64 subscript.

;## Classes ######################################################################

class MdBlock {
	kind := ""			; "paragraph" | "heading" | "item" | "code" | "rule" | "table"
	level := 0			; heading level 1-6, or list nesting depth (0-based) for items
	quote := 0			; blockquote nesting depth
	raw := ""			; inline Markdown of paragraphs, headings and items
	ordered := false	; item: numbered?
	number := 1			; item: its number
	paren := false		; item: "1)" instead of "1."
	check := ""			; item: "" | "o" (unchecked task box) | "x" (checked)
	breakAfter := false	; item: last line so far ended in two spaces
	lines := ""			; code: Array of lines
	rows := ""			; table: Array of rows, each an Array of raw cell strings (row 1 = header)
	aligns := ""		; table: Array of "l" | "c" | "r"
}

class MdList {
	markerIndent := 0
	contentColumn := 0
	ordered := false
	paren := false
	start := 1
	count := 0			; items seen after the first
	__New(markerIndent, contentColumn, ordered, paren, start) {
		this.markerIndent := markerIndent
		this.contentColumn := contentColumn
		this.ordered := ordered
		this.paren := paren
		this.start := start
	}
}

class MdNode {
	text := ""
	style := 0
	delim := ""			; "*", "_" or "~" while this node is an unresolved delimiter run
	count := 0
	orig := 0
	canOpen := false
	canClose := false
	pic := ""			; ready-made RTF picture group; when set, it is written instead of the text
	__New(text := "", style := 0) {
		this.text := text
		this.style := style
	}
}

;## Entry point ##################################################################

; hardBreaks := true makes every single newline inside a paragraph a line break
; (Obsidian / GitHub-comment style). The default (false) is standard Markdown:
; consecutive lines are joined into one wrapped paragraph.
; opts is an optional object literal that enables images - see the header comment.
MarkdownToRTF(md, hardBreaks := false, opts := "") {
	MdOpts(true, opts)
	refs := Map()
	refs.CaseSense := false
	blocks := MdParseBlocks(md, refs, hardBreaks)

	; Font table: f0 = body (Segoe UI), f1 = monospace (Consolas).
	; Color table: 1 = body text (black), 2 = blockquote text (gray),
	;              3 = link text (blue), 4 = code background (near-white).
	; Index 0 is intentionally empty -> RTF's "auto/none" color.
	rtf := "{\rtf1\ansi\ansicpg1252\deff0"
		. "{\fonttbl{\f0\fswiss Segoe UI;}{\f1\fmodern Consolas;}}"
		. "{\colortbl;\red0\green0\blue0;\red100\green100\blue100;\red0\green102\blue204;\red245\green245\blue245;}"
		. "\f0\fs22\cf1`n"

	body := ""
	for idx, block in blocks {
		nextBlock := (idx < blocks.Length) ? blocks[idx + 1] : ""
		body .= MdRenderBlock(block, nextBlock, refs)
	}
	return rtf body "}"
}

;## RTF output ###################################################################

MdRenderBlock(block, nextBlock, refs) {
	kind := block.kind
	qIndent := block.quote * 540

	if (kind = "paragraph") {
		inner := MdNodesToRtf(MdInlineNodes(block.raw, refs))
		if (block.quote)
			return "\pard\li" qIndent "\sa120\i\cf2 " inner "\i0\cf1\par`n"
		return "\pard\sa120 " inner "\par`n"
	}

	if (kind = "heading") {
		static sizes := Map(1, 36, 2, 32, 3, 28, 4, 24, 5, 22, 6, 22)
		fs := sizes[block.level]
		; Space before/after scaled to the header's own size so bigger headers
		; get proportionally more breathing room.
		sb := fs * 10
		sa := fs * 5
		inner := MdNodesToRtf(MdInlineNodes(block.raw, refs))
		return "\pard\li" qIndent "\sb" sb "\sa" sa "\b\fs" fs " " inner "\b0\fs22\par`n"
	}

	if (kind = "item") {
		lvl := block.level
		li := 720 + (lvl * 360) + qIndent
		if (block.check = "x") {
			marker := "\u9745?"
		} else if (block.check = "o") {
			marker := "\u9744?"
		} else if (block.ordered) {
			suffix := block.paren ? ")" : "."
			marker := block.number suffix
		} else {
			shape := Mod(lvl, 3)
			if (shape = 0)
				marker := "\u8226?"
			else if (shape = 1)
				marker := "\u9702?"
			else
				marker := "\u9642?"
		}
		sa := (IsObject(nextBlock) && nextBlock.kind = "item") ? 40 : 120
		inner := MdNodesToRtf(MdInlineNodes(block.raw, refs))
		return "\pard\tx" li "\li" li "\fi-360\sa" sa " " marker "\tab " inner "\par`n"
	}

	if (kind = "code") {
		out := ""
		lastLine := block.lines.Length
		for idx, ln in block.lines {
			sa := (idx = lastLine) ? 120 : 0
			out .= "\pard\li" (360 + qIndent) "\sb0\sa" sa "\highlight4\f1\fs20 " RtfEscapeText(ln) "\highlight0\f0\fs22\par`n"
		}
		return out
	}

	if (kind = "rule") {
		hr := ""
		loop 40
			hr .= "\u9472?"	; U+2500 box-drawing horizontal line
		return "\pard\li" qIndent "\sb60\sa120\fs16\cf2 " hr "\fs22\cf1\par`n"
	}

	if (kind = "table")
		return MdRenderTable(block, refs)

	return ""
}

MdRenderTable(block, refs) {
	rows := block.rows
	numCols := block.aligns.Length
	qIndent := block.quote * 540

	; Tables are monospaced text, so images in cells stay "[Image: alt]" notes.
	imgOpts := MdOpts()
	picsWere := imgOpts["pics"]
	imgOpts["pics"] := false

	; Parse every cell once; widths come from each cell's RENDERED text.
	cellNodes := []
	widths := []
	loop numCols
		widths.Push(3)	; floor width, so the separator line under short columns is still visible
	for _, row in rows {
		rowNodes := []
		loop numCols {
			raw := (A_Index <= row.Length) ? row[A_Index] : ""
			nodes := MdInlineNodes(raw, refs)
			rowNodes.Push(nodes)
			widths[A_Index] := Max(widths[A_Index], StrLen(MdNodesText(nodes)))
		}
		cellNodes.Push(rowNodes)
	}
	imgOpts["pics"] := picsWere

	out := ""
	lastRow := cellNodes.Length
	linePrefix := "\pard\li" (360 + qIndent) "\sb0\sa"
	lineStyle := "\highlight4\f1\fs20 "
	lineEnd := "\highlight0\f0\fs22\par`n"
	for r, rowNodes in cellNodes {
		line := ""
		loop numCols {
			c := A_Index
			nodes := rowNodes[c]
			pad := widths[c] - StrLen(MdNodesText(nodes))
			cellRtf := MdNodesToRtf(nodes)
			if (r = 1)
				cellRtf := "\b " cellRtf "\b0 "	; header row: bold as a whole
			al := block.aligns[c]
			if (al = "r") {
				cellRtf := MdRepeat(" ", pad) cellRtf
			} else if (al = "c") {
				half := pad // 2
				cellRtf := MdRepeat(" ", half) cellRtf MdRepeat(" ", pad - half)
			} else {
				cellRtf := cellRtf MdRepeat(" ", pad)
			}
			colSep := (c > 1) ? " | " : ""
			line .= colSep cellRtf
		}
		sa := (r = lastRow && r > 1) ? 120 : 0
		out .= linePrefix sa lineStyle line lineEnd

		; Separator line right under the header, built from the same widths.
		if (r = 1) {
			sepText := ""
			loop numCols {
				dashes := MdRepeat("-", widths[A_Index])
				sepJoin := (A_Index > 1) ? "-+-" : ""
				sepText .= sepJoin dashes
			}
			sa := (lastRow = 1) ? 120 : 0
			out .= linePrefix sa lineStyle sepText lineEnd
		}
	}
	return out
}

MdNodesToRtf(nodes) {
	out := ""
	for _, nd in nodes {
		if (nd.pic != "") {
			out .= nd.pic
			continue
		}
		txt := RtfEscapeText(nd.text)
		st := nd.style
		if (st = 0) {
			out .= txt
			continue
		}
		flags := ""
		if (st & 8)
			flags .= "\f1\highlight4"
		if (st & 1)
			flags .= "\b"
		if (st & 2)
			flags .= "\i"
		if (st & 4)
			flags .= "\strike"
		if (st & 16)
			flags .= "\ul"
		if (st & 32)
			flags .= "\super"
		if (st & 64)
			flags .= "\sub"
		out .= "{" flags " " txt "}"
	}
	return out
}

MdNodesText(nodes) {
	out := ""
	for _, nd in nodes
		out .= nd.text
	return out
}

; -------------------------------------------------------------------------------
RtfEscapeText(text) {
	; RTF metacharacters must be escaped before anything else touches the
	; string. Everything outside printable ASCII is written as \uN? (N is a
	; signed 16-bit value; characters above U+FFFF become a surrogate pair),
	; so the result is pure 7-bit text that no ANSI codepage can mangle.
	text := StrReplace(text, "\", "\\")
	text := StrReplace(text, "{", "\{")
	text := StrReplace(text, "}", "\}")
	if !RegExMatch(text, "[^\x20-\x7E]")
		return text

	out := ""
	loop parse text {
		code := Ord(A_LoopField)
		if (code = 11) {			; vertical tab = our hard line break marker
			out .= "\line "
		} else if (code = 9) {
			out .= "\tab "
		} else if (code > 65535) {	; a whole code point (not split into surrogates)
			cp := code - 0x10000
			hi := 0xD800 + (cp >> 10)
			lo := 0xDC00 + (cp & 0x3FF)
			out .= "\u" (hi - 65536) "?\u" (lo - 65536) "?"
		} else if (code > 127) {
			if (code > 32767)
				code -= 65536
			out .= "\u" code "?"
		} else if (code < 32) {
			out .= " "				; stray control characters
		} else {
			out .= A_LoopField
		}
	}
	return out
}

MdRepeat(str, count) {
	out := ""
	loop count
		out .= str
	return out
}

;## Regex table ##################################################################

MdRx() {
	static rx := ""
	if IsObject(rx)
		return rx
	bt := Chr(96) ; backtick - built via Chr() since AHK's own backtick-escaping rules
	              ; make raw backticks inside string/regex literals easy to get wrong.
	rx := Map()
	rx["fence"]      := "^( {0,3})(" bt "{3,}|~{3,})[ \t]*(.*)$"
	rx["atx"]        := "^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"
	rx["setext"]     := "^ {0,3}(=+|-+)[ \t]*$"
	rx["rule"]       := "^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"
	rx["list"]       := "^( *)([-+*]|(\d{1,9})([.)]))( +|$)(.*)$"
	rx["tabledelim"] := "^ {0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"
	rx["refdef"]     := "^ {0,3}\[([^\]^][^\]]*)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+(?:`"[^`"]*`"|'[^']*'|\([^)]*\)))?[ \t]*$"
	rx["comment"]    := "^\s*<!--.*-->\s*$"
	rx["autolink"]   := "i)^<([a-z][a-z0-9+.-]{1,31}:[^\s<>]*|[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+)>"
	rx["htmltag"]    := "i)^<(/?)(u|ins|sup|sub|br|b|strong|i|em|s|del|strike)\s*/?>"
	rx["task"]       := "^\[([ xX])\][ \t]+(.*)$"
	rx["wiki"]       := "^(!?)\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"
	rx["img"]        := "i)^<img\s[^>]*>"
	rx["imgname"]    := "i)\.(?:png|jpe?g|jfif|gif|bmp|webp|svg|tiff?|ico|avif)$"
	rx["sizehint"]   := "(\d+)(?:x(\d+))?$"
	return rx
}

;## Block parser #################################################################

MdParseBlocks(md, refs, hardBreaks := false) {
	rx := MdRx()
	bt := Chr(96)

	src := StrReplace(md, "`r`n", "`n")
	src := StrReplace(src, "`r", "`n")
	if (SubStr(src, 1, 1) = Chr(0xFEFF))
		src := SubStr(src, 2)

	; Pass 1: expand leading tabs, and collect + remove reference definitions
	; ("[label]: url") - but never inside fenced code.
	lines := []
	inFence := false
	for _, rawLine in StrSplit(src, "`n") {
		ln := MdExpandTabs(rawLine)
		stripped := MdStripQuote(ln, &qDummy)
		if RegExMatch(stripped, rx["fence"])
			inFence := !inFence
		if (!inFence && RegExMatch(ln, rx["refdef"], &rm)) {
			key := MdNormLabel(rm[1])
			if !refs.Has(key)
				refs[key] := rm[2]
			continue
		}
		lines.Push(ln)
	}

	; Pass 2: blocks.
	blocks := []
	para := []			; lines of the paragraph being collected
	paraQuote := 0
	lists := []			; stack of open MdList objects
	item := ""			; the list item that continuation lines belong to
	afterBlank := false
	total := lines.Length
	i := 1				; index of the NEXT line (already incremented while a line is processed)

	while (i <= total) {
		ln := lines[i]
		i++
		content := MdStripQuote(ln, &quote)
		blank := (Trim(content) = "")

		; --- Fenced code block -------------------------------------------------
		if (RegExMatch(content, rx["fence"], &fm) && !(SubStr(fm[2], 1, 1) = bt && InStr(fm[3], bt))) {
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
			lists.Length := 0
			item := ""
			marker := fm[2]
			fenceCh := SubStr(marker, 1, 1)
			fenceIndent := StrLen(fm[1])
			closeRx := "^ {0,3}" ((fenceCh = bt) ? bt : "~") "{" StrLen(marker) ",}[ \t]*$"
			cb := MdBlock()
			cb.kind := "code"
			cb.quote := quote
			cb.lines := []
			while (i <= total) {
				cl := MdStripQuote(lines[i], &qDummy, quote)
				i++
				if RegExMatch(cl, closeRx)
					break
				cb.lines.Push(MdRemoveIndent(cl, fenceIndent))
			}
			blocks.Push(cb)
			afterBlank := false
			continue
		}

		; --- Blank line: ends a paragraph, nothing else -------------------------
		if (blank) {
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
			afterBlank := true
			continue
		}

		; --- HTML comment on its own line: ends paragraph and list, shows nothing
		if RegExMatch(content, rx["comment"]) {
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
			lists.Length := 0
			item := ""
			continue
		}

		indent := StrLen(content) - StrLen(LTrim(content, " "))
		isRule := RegExMatch(content, rx["rule"])
		isItem := false
		if (!isRule && RegExMatch(content, rx["list"], &lm)) {
			isItem := true
			; Only "1." may interrupt a paragraph; and 4+ spaces with no open list is code.
			if (para.Length && !lists.Length && lm[3] != "" && lm[3] != "1")
				isItem := false
			else if (indent >= 4 && !lists.Length)
				isItem := false
		}

		; --- List continuation lines ----------------------------------------
		if (lists.Length && IsObject(item) && !isItem) {
			startsBlock := RegExMatch(content, rx["atx"]) || isRule || RegExMatch(content, rx["fence"])
			if (indent >= lists[lists.Length].contentColumn || (!afterBlank && !startsBlock)) {
				prevText := item.raw
				if (item.breakAfter)
					prevText .= "  "
				item.raw := MdJoinLines([prevText, LTrim(content)], hardBreaks)
				item.breakAfter := (SubStr(content, -2) = "  ")
				afterBlank := false
				continue
			}
			lists.Length := 0
			item := ""
		}

		; --- Setext heading: a paragraph followed by === or --- --------------------
		if (para.Length && quote = paraQuote && RegExMatch(content, rx["setext"], &sm)) {
			hb := MdBlock()
			hb.kind := "heading"
			hb.level := (SubStr(sm[1], 1, 1) = "=") ? 1 : 2
			hb.raw := MdJoinLines(para, hardBreaks)
			hb.quote := quote
			blocks.Push(hb)
			para.Length := 0
			afterBlank := false
			continue
		}

		; --- ATX heading --------------------------------------------------------
		if RegExMatch(content, rx["atx"], &hm) {
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
			lists.Length := 0
			item := ""
			hb := MdBlock()
			hb.kind := "heading"
			hb.level := StrLen(hm[1])
			hb.raw := Trim(hm[2])
			hb.quote := quote
			blocks.Push(hb)
			afterBlank := false
			continue
		}

		; --- Horizontal rule ------------------------------------------------------
		if (isRule) {
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
			lists.Length := 0
			item := ""
			rb := MdBlock()
			rb.kind := "rule"
			rb.quote := quote
			blocks.Push(rb)
			afterBlank := false
			continue
		}

		; --- Table: a row of cells, then a delimiter row with the same cell count -
		if (!para.Length && InStr(content, "|") && i <= total) {
			nextContent := MdStripQuote(lines[i], &qDummy)
			if RegExMatch(nextContent, rx["tabledelim"]) {
				headCells := MdSplitCells(content)
				delimCells := MdSplitCells(nextContent)
				if (headCells.Length = delimCells.Length) {
					lists.Length := 0
					item := ""
					aligns := []
					for _, dc in delimCells {
						startsColon := (SubStr(dc, 1, 1) = ":")
						endsColon := (SubStr(dc, -1) = ":")
						if (startsColon && endsColon)
							aligns.Push("c")
						else if (endsColon)
							aligns.Push("r")
						else
							aligns.Push("l")
					}
					tb := MdBlock()
					tb.kind := "table"
					tb.quote := quote
					tb.rows := [headCells]
					tb.aligns := aligns
					i++		; consume the delimiter row
					while (i <= total) {
						rowText := MdStripQuote(lines[i], &qDummy)
						if (Trim(rowText) = "" || !InStr(rowText, "|"))
							break
						tb.rows.Push(MdSplitCells(rowText))
						i++
					}
					MdFlushPara(blocks, para, paraQuote, hardBreaks)
					blocks.Push(tb)
					afterBlank := false
					continue
				}
			}
		}

		; --- List item --------------------------------------------------------------
		if (isItem) {
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
			ordered := (lm[3] != "")
			number := ordered ? Integer(lm[3]) : 1
			spaces := StrLen(lm[5])
			contentColumn := indent + StrLen(lm[2]) + ((spaces >= 1 && spaces <= 4) ? spaces : 1)
			paren := (lm[4] = ")")
			rawText := Trim(lm[6])
			endsTwoSpaces := (SubStr(lm[6], -2) = "  ")

			newList := true
			while (lists.Length && indent < lists[lists.Length].markerIndent)
				lists.Pop()
			if (lists.Length && indent >= lists[lists.Length].contentColumn) {
				lists.Push(MdList(indent, contentColumn, ordered, paren, number))	; nested list
			} else if (lists.Length) {
				cur := lists[lists.Length]
				; bullets after numbers (or the reverse), or "1)" after "1.", start a new list (CommonMark)
				if (cur.ordered != ordered || (ordered && cur.paren != paren)) {
					lists[lists.Length] := MdList(indent, contentColumn, ordered, paren, number)
				} else {
					cur.contentColumn := contentColumn
					newList := false
				}
			} else {
				lists.Push(MdList(indent, contentColumn, ordered, paren, number))
			}
			cur := lists[lists.Length]
			if (newList)
				cur.count := 0
			else
				cur.count += 1

			checkState := ""
			if RegExMatch(rawText, rx["task"], &cm) {
				checkState := (cm[1] = " ") ? "o" : "x"
				rawText := cm[2]
			}

			item := MdBlock()
			item.kind := "item"
			item.level := lists.Length - 1
			item.ordered := ordered
			item.number := cur.start + cur.count
			item.paren := cur.paren
			item.check := checkState
			item.raw := rawText
			item.quote := quote
			item.breakAfter := endsTwoSpaces
			blocks.Push(item)
			afterBlank := false
			continue
		}

		; --- Indented code block --------------------------------------------------
		if (indent >= 4 && !para.Length) {
			cb := MdBlock()
			cb.kind := "code"
			cb.quote := quote
			cb.lines := []
			i--		; start again from this line
			while (i <= total) {
				cl := MdStripQuote(lines[i], &qDummy, quote)
				if (Trim(cl) != "" && (StrLen(cl) - StrLen(LTrim(cl, " "))) < 4)
					break
				cb.lines.Push((StrLen(cl) >= 4) ? SubStr(cl, 5) : "")
				i++
			}
			while (cb.lines.Length && Trim(cb.lines[cb.lines.Length]) = "")
				cb.lines.Pop()		; trailing blank lines
			blocks.Push(cb)
			afterBlank := false
			continue
		}

		; --- Default: paragraph text ----------------------------------------------
		if (para.Length && quote != paraQuote)
			MdFlushPara(blocks, para, paraQuote, hardBreaks)
		if (!para.Length)
			paraQuote := quote
		para.Push(content)
		afterBlank := false
	}
	MdFlushPara(blocks, para, paraQuote, hardBreaks)
	return blocks
}

MdFlushPara(blocks, para, quote, hardBreaks := false) {
	if (!para.Length)
		return
	; Obsidian callout: "> [!info] Title" - the title line becomes a bold paragraph of its own.
	if (quote && RegExMatch(para[1], "^\[!([A-Za-z-]+)\][+-]?[ \t]*(.*)$", &co)) {
		title := Trim(co[2])
		if (title = "")
			title := StrTitle(co[1])
		tb := MdBlock()
		tb.kind := "paragraph"
		tb.raw := "**" title "**"
		tb.quote := quote
		blocks.Push(tb)
		para.RemoveAt(1)
		if (!para.Length)
			return
	}
	b := MdBlock()
	b.kind := "paragraph"
	b.raw := MdJoinLines(para, hardBreaks)
	b.quote := quote
	blocks.Push(b)
	para.Length := 0
}

; The lines of a paragraph: a line ending in two spaces or a backslash is a hard
; line break (marked with a vertical tab); the others are joined with a space.
MdJoinLines(arr, hardBreaks := false) {
	vt := Chr(11)
	out := ""
	lastIdx := arr.Length
	for idx, ln in arr {
		s := LTrim(ln)
		if (idx < lastIdx) {
			if (SubStr(s, -2) = "  ") {
				out .= RTrim(s) vt
			} else if (SubStr(s, -1) = "\" && SubStr(s, -2) != "\\") {
				out .= SubStr(s, 1, -1) vt
			} else if (hardBreaks) {
				out .= RTrim(s) vt
			} else {
				out .= RTrim(s) " "
			}
		} else {
			out .= RTrim(s)
		}
	}
	return out
}

; Strips up to maxLevels leading "> " markers; the depth found is returned in quote.
MdStripQuote(line, &quote, maxLevels := 99) {
	quote := 0
	while (quote < maxLevels && RegExMatch(line, "^ {0,3}> ?", &m)) {
		quote++
		line := SubStr(line, StrLen(m[0]) + 1)
	}
	return line
}

; Leading tabs only (they matter for indentation) become spaces, to multiples of 4.
MdExpandTabs(ln) {
	if !InStr(ln, "`t")
		return ln
	out := ""
	col := 0
	p := 1
	total := StrLen(ln)
	while (p <= total) {
		ch := SubStr(ln, p, 1)
		if (ch = " ") {
			out .= " "
			col++
		} else if (ch = "`t") {
			pad := 4 - Mod(col, 4)
			out .= MdRepeat(" ", pad)
			col += pad
		} else {
			break
		}
		p++
	}
	return out SubStr(ln, p)
}

MdRemoveIndent(ln, count) {
	p := 1
	total := StrLen(ln)
	while (p <= count && p <= total && SubStr(ln, p, 1) = " ")
		p++
	return SubStr(ln, p)
}

; Splits a table row at unescaped pipes ("\|" becomes a literal pipe).
MdSplitCells(row) {
	row := Trim(row)
	if (SubStr(row, 1, 1) = "|")
		row := SubStr(row, 2)
	if (SubStr(row, -1) = "|" && SubStr(row, -2) != "\|")
		row := SubStr(row, 1, -1)
	cells := []
	cell := ""
	p := 1
	total := StrLen(row)
	while (p <= total) {
		ch := SubStr(row, p, 1)
		if (ch = "\" && SubStr(row, p + 1, 1) = "|") {
			cell .= "|"
			p += 2
			continue
		}
		if (ch = "|") {
			cells.Push(Trim(cell))
			cell := ""
			p++
			continue
		}
		cell .= ch
		p++
	}
	cells.Push(Trim(cell))
	return cells
}

MdNormLabel(label) => RegExReplace(Trim(label), "\s+", " ")

;## Inline parser ################################################################

; Markdown text -> Array of MdNode (text + style flags), delimiters resolved.
MdInlineNodes(text, refs, htmlStyle := 0) {
	nodes := MdParseNodes(text, refs, htmlStyle)
	MdProcessEmphasis(nodes)
	out := []
	for _, nd in nodes {
		if (nd.delim != "") {			; an unmatched delimiter run is just text
			if (nd.count = 0)
				continue
			nd.text := MdRepeat(nd.delim, nd.count)
			nd.delim := ""
		}
		if (nd.text = "")
			continue
		out.Push(nd)
	}
	return out
}

MdParseNodes(s, refs, htmlStyle := 0) {
	rx := MdRx()
	bt := Chr(96)
	vt := Chr(11)
	nodes := []
	buf := ""
	total := StrLen(s)
	i := 1

	while (i <= total) {
		c := SubStr(s, i, 1)

		; Backslash escape of ASCII punctuation.
		if (c = "\" && i < total && MdIsAsciiPunct(SubStr(s, i + 1, 1))) {
			buf .= SubStr(s, i + 1, 1)
			i += 2
			continue
		}

		; Code span: a backtick run closed by a run of the same length.
		if (c = bt) {
			runLen := MdCountRun(s, i, bt)
			closeAt := MdFindBacktickRun(s, i + runLen, runLen)
			if (closeAt) {
				MdFlush(nodes, &buf, htmlStyle)
				code := SubStr(s, i + runLen, closeAt - (i + runLen))
				code := StrReplace(code, vt, " ")
				if (StrLen(code) >= 2 && SubStr(code, 1, 1) = " " && SubStr(code, -1) = " " && Trim(code) != "")
					code := SubStr(code, 2, -1)
				nodes.Push(MdNode(code, htmlStyle | 8))
				i := closeAt + runLen
			} else {
				buf .= MdRepeat(bt, runLen)
				i += runLen
			}
			continue
		}

		; Obsidian wiki-links: [[Page]], [[Page|alias]], and embeds ![[file]].
		if ((c = "[" || c = "!") && RegExMatch(SubStr(s, i, 300), rx["wiki"], &wm)) {
			MdFlush(nodes, &buf, htmlStyle)
			if (wm[1] = "!") {
				; ![[file.png]], ![[file.png|300]], ![[file.png|300x200]], ![[file.png|alt text]]
				embedName := Trim(wm[2])
				hintW := 0, hintH := 0, alt := ""
				if RegExMatch(wm[3], "^" . rx["sizehint"], &hm) {
					hintW := Integer(hm[1])
					hintH := (hm[2] != "") ? Integer(hm[2]) : 0
				} else {
					alt := Trim(wm[3])
				}
				if RegExMatch(embedName, rx["imgname"])
					nodes.Push(MdImageNode(embedName, (alt != "") ? alt : embedName, hintW, hintH, htmlStyle))
				else
					nodes.Push(MdNode("[Embed: " embedName "]", htmlStyle | 2))
			} else {
				nodes.Push(MdNode((wm[3] != "") ? wm[3] : wm[2], htmlStyle))
			}
			i += StrLen(wm[0])
			continue
		}

		; Links and images.
		if (c = "[" || (c = "!" && SubStr(s, i + 1, 1) = "[")) {
			openAt := (c = "!") ? i + 1 : i
			link := MdParseLink(s, openAt, refs)
			if IsObject(link) {
				MdFlush(nodes, &buf, htmlStyle)
				inner := MdInlineNodes(link.label, refs, htmlStyle)
				if (c = "!") {
					; ![alt](src), ![alt|300](src), ![alt|300x200](src)
					alt := MdNodesText(inner)
					hintW := 0, hintH := 0
					if RegExMatch(alt, "\|" . rx["sizehint"], &hm) {
						hintW := Integer(hm[1])
						hintH := (hm[2] != "") ? Integer(hm[2]) : 0
						alt := SubStr(alt, 1, StrLen(alt) - StrLen(hm[0]))
					}
					nodes.Push(MdImageNode(link.url, Trim(alt), hintW, hintH, htmlStyle))
				} else {
					for _, nd in inner
						nodes.Push(nd)
					; Show the target after the label, unless it is the label itself or an in-page anchor.
					if (link.url != "" && SubStr(link.url, 1, 1) != "#" && link.url != MdNodesText(inner))
						nodes.Push(MdNode(" (" link.url ")", htmlStyle))
				}
				i := link.endPos
				continue
			}
		}

		; Autolinks, <br> and the supported inline HTML tags.
		if (c = "<") {
			rest := SubStr(s, i, 2000)
			if RegExMatch(rest, rx["autolink"], &am) {
				MdFlush(nodes, &buf, htmlStyle)
				nodes.Push(MdNode(am[1], htmlStyle))
				i += StrLen(am[0])
				continue
			}
			if RegExMatch(rest, rx["img"], &gm) {
				; <img src="x.png" alt="..." width="300" height="200">
				MdFlush(nodes, &buf, htmlStyle)
				hintW := 0, hintH := 0
				if RegExMatch(MdAttr(gm[0], "width"), "^(\d+)(?:px)?$", &hm)
					hintW := Integer(hm[1])
				if RegExMatch(MdAttr(gm[0], "height"), "^(\d+)(?:px)?$", &hm)
					hintH := Integer(hm[1])
				nodes.Push(MdImageNode(MdAttr(gm[0], "src"), MdAttr(gm[0], "alt"), hintW, hintH, htmlStyle))
				i += StrLen(gm[0])
				continue
			}
			if RegExMatch(rest, rx["htmltag"], &tm) {
				name := StrLower(tm[2])
				if (name = "br") {
					buf .= vt
				} else {
					MdFlush(nodes, &buf, htmlStyle)
					flag := MdTagFlag(name)
					if (tm[1] = "/")
						htmlStyle := htmlStyle & ~flag
					else
						htmlStyle := htmlStyle | flag
				}
				i += StrLen(tm[0])
				continue
			}
		}

		; Emphasis delimiter run (* _ ~~): classify as opener/closer by flanking.
		if (c = "*" || c = "_" || (c = "~" && SubStr(s, i + 1, 1) = "~")) {
			runLen := MdCountRun(s, i, c)
			before := (i > 1) ? SubStr(s, i - 1, 1) : " "
			after := (i + runLen <= total) ? SubStr(s, i + runLen, 1) : " "
			afterSp := MdIsSpace(after)
			beforeSp := MdIsSpace(before)
			afterPu := MdIsPunct(after)
			beforePu := MdIsPunct(before)
			leftF := !afterSp && (!afterPu || beforeSp || beforePu)
			rightF := !beforeSp && (!beforePu || afterSp || afterPu)
			MdFlush(nodes, &buf, htmlStyle)
			d := MdNode("", htmlStyle)
			d.delim := c
			d.count := runLen
			d.orig := runLen
			if (c = "_") {
				d.canOpen := leftF && (!rightF || beforePu)
				d.canClose := rightF && (!leftF || afterPu)
			} else {
				d.canOpen := leftF
				d.canClose := rightF
			}
			nodes.Push(d)
			i += runLen
			continue
		}

		buf .= c
		i++
	}
	MdFlush(nodes, &buf, htmlStyle)
	return nodes
}

MdFlush(nodes, &buf, style) {
	if (buf != "") {
		nodes.Push(MdNode(buf, style))
		buf := ""
	}
}

MdTagFlag(name) {
	if (name = "sup")
		return 32
	if (name = "sub")
		return 64
	if (name = "b" || name = "strong")
		return 1
	if (name = "i" || name = "em")
		return 2
	if (name = "s" || name = "del" || name = "strike")
		return 4
	return 16	; u, ins
}

; CommonMark's "process emphasis", in short: each closing run is matched with the
; nearest opening run of the same character; the text between gets bold (two
; characters) or italic (one), or strikethrough for ~~.
MdProcessEmphasis(nodes) {
	c := 1
	while (c <= nodes.Length) {
		closer := nodes[c]
		if (closer.delim = "" || !closer.canClose || closer.count = 0) {
			c++
			continue
		}
		matched := false
		o := c - 1
		while (o >= 1) {
			opener := nodes[o]
			if (opener.delim != closer.delim || !opener.canOpen || opener.count = 0) {
				o--
				continue
			}
			; "Rule of 3": runs that can both open and close only match if their sizes don't sum to a multiple of 3.
			if (closer.delim != "~" && (opener.canClose || closer.canOpen)
				&& Mod(opener.orig + closer.orig, 3) = 0
				&& !(Mod(opener.orig, 3) = 0 && Mod(closer.orig, 3) = 0)) {
				o--
				continue
			}
			if (closer.delim = "~") {
				if (opener.count < 2 || closer.count < 2) {
					o--
					continue
				}
				use := 2
				style := 4
			} else {
				use := (opener.count >= 2 && closer.count >= 2) ? 2 : 1
				style := (use = 2) ? 1 : 2
			}
			k := o + 1
			while (k < c) {
				nodes[k].style := nodes[k].style | style
				if (nodes[k].delim != "") {		; runs in between can no longer match
					nodes[k].canOpen := false
					nodes[k].canClose := false
				}
				k++
			}
			opener.count -= use
			closer.count -= use
			matched := true
			break
		}
		if (!matched || closer.count = 0)	; leftover of this run may close another opener
			c++
	}
}

; [label](url "title"), [label][ref], [label][] or [label], starting at the "[".
; Returns {label, url, endPos} (endPos = index just past the link) or "" if it isn't one.
MdParseLink(s, openAt, refs) {
	bt := Chr(96)
	total := StrLen(s)
	depth := 0
	closeAt := 0
	p := openAt
	while (p <= total) {
		ch := SubStr(s, p, 1)
		if (ch = "\") {
			p += 2
			continue
		}
		if (ch = bt) {
			runLen := MdCountRun(s, p, bt)
			endAt := MdFindBacktickRun(s, p + runLen, runLen)
			p := endAt ? endAt + runLen : p + runLen
			continue
		}
		if (ch = "[") {
			depth++
		} else if (ch = "]") {
			depth--
			if (depth = 0) {
				closeAt := p
				break
			}
		}
		p++
	}
	if (!closeAt)
		return ""

	label := SubStr(s, openAt + 1, closeAt - openAt - 1)
	pos := closeAt + 1

	; Inline link: (url "title")
	if (SubStr(s, pos, 1) = "(") {
		p := pos + 1
		while (p <= total && MdIsSpace(SubStr(s, p, 1)))
			p++
		url := ""
		if (SubStr(s, p, 1) = "<") {
			gt := InStr(s, ">", false, p)
			if (!gt)
				return ""
			url := SubStr(s, p + 1, gt - p - 1)
			p := gt + 1
		} else {
			startAt := p
			parens := 0
			while (p <= total) {
				ch := SubStr(s, p, 1)
				if (ch = "\" && p < total) {
					p += 2
					continue
				}
				if (MdIsSpace(ch))
					break
				if (ch = "(") {
					parens++
				} else if (ch = ")") {
					if (parens = 0)
						break
					parens--
				}
				p++
			}
			url := RegExReplace(SubStr(s, startAt, p - startAt), "\\([!-/:-@\[-" bt "{-~])", "$1")
		}
		while (p <= total && MdIsSpace(SubStr(s, p, 1)))
			p++
		ch := SubStr(s, p, 1)
		if (ch = "`"" || ch = "'" || ch = "(") {		; title: ignored
			endCh := (ch = "(") ? ")" : ch
			titleEnd := InStr(s, endCh, false, p + 1)
			if (!titleEnd)
				return ""
			p := titleEnd + 1
			while (p <= total && MdIsSpace(SubStr(s, p, 1)))
				p++
		}
		if (p > total || SubStr(s, p, 1) != ")")
			return ""
		return {label: label, url: url, endPos: p + 1}
	}

	; Reference links: [label][ref] and [label][]
	if (SubStr(s, pos, 1) = "[") {
		endAt := InStr(s, "]", false, pos + 1)
		if (endAt) {
			refName := SubStr(s, pos + 1, endAt - pos - 1)
			key := MdNormLabel((refName = "") ? label : refName)
			if refs.Has(key)
				return {label: label, url: refs[key], endPos: endAt + 1}
		}
	}
	; Shortcut reference: [label]
	key := MdNormLabel(label)
	if refs.Has(key)
		return {label: label, url: refs[key], endPos: closeAt + 1}
	return ""
}

MdCountRun(s, i, ch) {
	n := 0
	total := StrLen(s)
	while (i + n <= total && SubStr(s, i + n, 1) = ch)
		n++
	return n
}

; Index of the next backtick run of exactly runLen backticks at or after "from", or 0.
MdFindBacktickRun(s, from, runLen) {
	bt := Chr(96)
	p := from
	total := StrLen(s)
	while (p <= total) {
		if (SubStr(s, p, 1) = bt) {
			r := MdCountRun(s, p, bt)
			if (r = runLen)
				return p
			p += r
		} else {
			p++
		}
	}
	return 0
}

MdIsAsciiPunct(ch) {
	c := Ord(ch)
	return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)
}

; Punctuation for flanking purposes: ASCII punctuation plus Unicode punctuation and symbols.
MdIsPunct(ch) {
	if (ch = "")
		return false
	if MdIsAsciiPunct(ch)
		return true
	return RegExMatch(ch, "^[\p{P}\p{S}]$") ? true : false
}

MdIsSpace(ch) {
	if (ch = "")
		return true
	c := Ord(ch)
	return (c <= 32 || c = 160 || c = 0x3000)
}

;## Images ######################################################################

; Options for the current conversion. MarkdownToRTF resets them on every call
; (MdOpts(true, opts)); everything else just reads them with MdOpts().
MdOpts(reset := false, user := "") {
	static o := Map()
	if !reset
		return o
	o := Map()
	o["baseDir"] := ""
	o["maxWidth"] := 8000
	o["maxBytes"] := 4194304
	o["imageDirs"] := []
	o["warn"] := ""
	o["dpi"] := A_ScreenDPI
	o["maxPixels"] := 40000000		; source image, width x height (decoding needs 4 bytes per pixel)
	o["maxTotalBytes"] := 8388608	; bitmap data embedded per document (the RTF holds it twice over, as hex)
	o["usedBytes"] := 0
	if IsObject(user) {
		v := MdOptGet(user, "baseDir")
		if (v != "")
			o["baseDir"] := RTrim(v, "\/")
		v := MdOptGet(user, "maxWidth")
		if (IsInteger(v) && v > 0)
			o["maxWidth"] := Integer(v)
		v := MdOptGet(user, "maxBytes")
		if (IsInteger(v) && v > 0)
			o["maxBytes"] := Integer(v)
		v := MdOptGet(user, "imageDirs")
		if IsObject(v)
			for _, d in v
				o["imageDirs"].Push(RTrim(d, "\/"))
		v := MdOptGet(user, "warn")
		if IsObject(v)
			o["warn"] := v
		v := MdOptGet(user, "dpi")
		if (IsInteger(v) && v >= 48 && v <= 960)
			o["dpi"] := Integer(v)
		v := MdOptGet(user, "maxPixels")
		if (IsInteger(v) && v > 0)
			o["maxPixels"] := Integer(v)
		v := MdOptGet(user, "maxTotalBytes")
		if (IsInteger(v) && v > 0)
			o["maxTotalBytes"] := Integer(v)
	}
	o["pics"] := (o["baseDir"] != "")	; false while rendering table cells
	return o
}

MdOptGet(user, name) {	; the options may be an object literal or a Map
	if (Type(user) = "Map")
		return user.Has(name) ? user[name] : ""
	return user.HasProp(name) ? user.%name% : ""
}

MdWarn(msg) {
	cb := MdOpts()["warn"]
	if IsObject(cb)
		try cb(msg)
}

; An image as an inline node: a picture (node.pic) when the file can be embedded,
; otherwise an italic "[Image ...]" note that says why. Never fails silently.
MdImageNode(src, alt, hintW, hintH, style) {
	opts := MdOpts()
	note := style | 2
	src := Trim(src)

	; Remote images are never fetched.
	if RegExMatch(src, "i)^https?://") {
		shown := (alt != "") ? "[Image: " alt " (" src ")]" : "[Image: " src "]"
		return MdNode(shown, note)
	}
	; Not enabled (no baseDir), inside a table, or not a file reference (data:, file:, ...).
	if (!opts["pics"] || src = "" || RegExMatch(src, "i)^[a-z][a-z0-9+.-]+:")) {
		shown := (alt != "") ? "[Image: " alt "]" : "[Image]"
		return MdNode(shown, note)
	}

	path := MdResolveImage(src)
	if (path = "") {
		MdWarn("Image not found: " src)
		shownName := MdUrlDecode(src)
		return MdNode("[Image missing: " shownName "]", note)
	}
	SplitPath(path, &fileName)

	try {
		size := FileGetSize(path)
		buf := ""
		if (size <= opts["maxBytes"])
			buf := FileRead(path, "RAW")
	} catch {
		MdWarn("Image could not be read: " path)
		return MdNode("[Image could not be loaded: " fileName "]", note)
	}
	if (size > opts["maxBytes"]) {
		MdWarn("Image too large (" size " bytes, limit " opts["maxBytes"] "): " path)
		return MdNode("[Image too large: " fileName "]", note)
	}

	; Identify the format from the header, and read the pixel size from it.
	kind := ""
	pxW := 0
	pxH := 0
	if (buf.Size >= 24 && NumGet(buf, 0, "UInt") = 0x474E5089 && NumGet(buf, 4, "UInt") = 0x0A1A0A0D
		&& NumGet(buf, 12, "UInt") = 0x52444849) {		; PNG signature, then an IHDR chunk
		kind := "png"
		pxW := MdBE32(buf, 16)
		pxH := MdBE32(buf, 20)
	} else if (buf.Size >= 4 && NumGet(buf, 0, "UChar") = 0xFF && NumGet(buf, 1, "UChar") = 0xD8
		&& NumGet(buf, 2, "UChar") = 0xFF) {			; JPEG
		if MdJpegSize(buf, &pxW, &pxH)
			kind := "jpeg"
	}
	if (kind = "" || pxW < 1 || pxH < 1 || pxW > 32000 || pxH > 32000) {
		MdWarn("Image format not supported or damaged: " path)
		return MdNode("[Image format not supported: " fileName "]", note)
	}
	if (pxW * pxH > opts["maxPixels"]) {	; checked before decoding: GDI+ would need 4 bytes per pixel
		MdWarn("Image too large (" pxW "x" pxH " px, limit " opts["maxPixels"] " pixels): " path)
		return MdNode("[Image too large: " fileName "]", note)
	}

	; Size in twips: natural size at 96 dpi (15 twips per pixel) or the width hint,
	; shrunk - never enlarged - to fit maxWidth, keeping the aspect ratio.
	if (hintW > 0) {
		twW := hintW * 15
		twH := (hintH > 0) ? hintH * 15 : Round(twW * pxH / pxW)
	} else {
		twW := pxW * 15
		twH := pxH * 15
	}
	maxW := opts["maxWidth"]
	if (twW > maxW) {
		twH := Round(twH * maxW / twW)
		twW := maxW
	}
	twW := Max(twW, 15)
	twH := Max(twH, 15)
	himW := Round(twW * 2540 / 1440)		; \picw / \pich are in 0.01 mm units
	himH := Round(twH * 2540 / 1440)

	; Embedded as a plain bitmap, not as \pngblip / \jpegblip: Msftedit (tested on
	; 10.0.26100) reserves no space for PNG/JPEG blips and draws nothing, even with
	; an OLE callback, but it does draw \dibitmap pictures. The bitmap gets as many
	; pixels as the picture covers on screen (twips at opts.dpi), never more than the
	; file has, so a big screenshot shown small does not bloat the RTF.
	bmpW := Max(1, Min(pxW, Round(twW * opts["dpi"] / 1440)))
	bmpH := Max(1, Round(twH * bmpW / twW))
	rowBytes := (bmpW * 3 + 3) & ~3		; DIB rows are padded to 4 bytes
	dibBytes := 40 + rowBytes * bmpH
	if (opts["usedBytes"] + dibBytes > opts["maxTotalBytes"]) {	; e.g. many tall screenshots on one page
		MdWarn("Image skipped, the document's picture limit (" opts["maxTotalBytes"] " bytes) is reached: " path)
		return MdNode("[Image not shown, too many pictures on this page: " fileName "]", note)
	}
	why := ""
	hex := MdDibHex(buf, bmpW, bmpH, rowBytes, &why)
	if (hex = "") {
		MdWarn("Image could not be decoded (" why "): " path)
		return MdNode("[Image could not be loaded: " fileName "]", note)
	}
	opts["usedBytes"] += dibBytes

	label := (alt != "") ? alt : fileName
	nd := MdNode("[Image: " label "]", style)
	nd.pic := "{\pict\dibitmap0\wbmbitspixel24\wbmplanes1\wbmwidthbytes" rowBytes
		. "\picw" himW "\pich" himH "\picwgoal" twW "\pichgoal" twH " " hex "}"
	return nd
}

; Decodes a PNG/JPEG file image (buf) with GDI+, scaled to bmpW x bmpH, and returns
; the hex text of a packed 24-bit DIB (BITMAPINFOHEADER + bottom-up rows of stride
; bytes) for \dibitmap0, or "" with the reason in why. Transparency is flattened
; onto white.
MdDibHex(buf, bmpW, bmpH, stride, &why) {
	static PixelFormat24bppRGB := 0x21808
	if !MdGdiplusReady() {
		why := "GDI+ could not be started"
		return ""
	}
	stream := 0, pSrc := 0, pDst := 0, gfx := 0, locked := false
	bd := Buffer(16 + 2 * A_PtrSize, 0)	; BitmapData
	try {
		stream := DllCall("shlwapi\SHCreateMemStream", "Ptr", buf, "UInt", buf.Size, "Ptr")	; copies buf
		if !stream
			throw Error("no memory stream")
		if (st := DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", stream, "Ptr*", &pSrc, "Int"))
			throw Error("GDI+ could not decode it, status " st)
		if (st := DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", bmpW, "Int", bmpH, "Int", 0, "Int", PixelFormat24bppRGB, "Ptr", 0, "Ptr*", &pDst, "Int"))
			throw Error("GDI+ could not create a " bmpW "x" bmpH " bitmap, status " st)
		DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pDst, "Ptr*", &gfx, "Int")
		if !gfx
			throw Error("no GDI+ graphics")
		DllCall("gdiplus\GdipGraphicsClear", "Ptr", gfx, "UInt", 0xFFFFFFFF, "Int")	; white under any transparency
		DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7, "Int")		; high quality bicubic
		DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gfx, "Int", 2, "Int")		; high quality (no shifted edges)
		if (st := DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gfx, "Ptr", pSrc, "Int", 0, "Int", 0, "Int", bmpW, "Int", bmpH, "Int"))
			throw Error("GDI+ could not draw it, status " st)
		DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx), gfx := 0

		rect := Buffer(16, 0)
		NumPut("Int", 0, "Int", 0, "Int", bmpW, "Int", bmpH, rect)
		if (st := DllCall("gdiplus\GdipBitmapLockBits", "Ptr", pDst, "Ptr", rect, "UInt", 1, "Int", PixelFormat24bppRGB, "Ptr", bd, "Int"))	; ImageLockModeRead
			throw Error("GDI+ could not lock the bitmap, status " st)
		locked := true
		srcStride := NumGet(bd, 8, "Int")
		scan0 := NumGet(bd, 16, "Ptr")

		dib := Buffer(40 + stride * bmpH, 0)
		NumPut("UInt", 40, "Int", bmpW, "Int", bmpH, "UShort", 1, "UShort", 24, "UInt", 0	; BI_RGB
			, "UInt", stride * bmpH, "Int", 3780, "Int", 3780, "UInt", 0, "UInt", 0, dib)	; 3780 px/m = 96 dpi
		loop bmpH	; GDI+ rows are top-down, a DIB's are bottom-up
			DllCall("RtlMoveMemory", "Ptr", dib.Ptr + 40 + (bmpH - A_Index) * stride
				, "Ptr", scan0 + (A_Index - 1) * srcStride, "UPtr", bmpW * 3)
	} catch as Err {
		why := Err.Message
		return ""
	} finally {
		if locked
			DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", pDst, "Ptr", bd)
		if gfx
			DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)
		if pDst
			DllCall("gdiplus\GdipDisposeImage", "Ptr", pDst)
		if pSrc
			DllCall("gdiplus\GdipDisposeImage", "Ptr", pSrc)
		if stream
			ObjRelease(stream)
	}
	hex := MdHexOf(dib)
	if (hex = "")
		why := "hex encoding failed"
	return hex
}

; Starts GDI+ once for the life of the script. Separate from Keybird's own
; Gdip_Startup(): GDI+ counts startups, so neither shuts the other down. The
; library is loaded explicitly so DllCall doesn't unload it between calls.
MdGdiplusReady() {
	static token := 0, tried := false
	if tried
		return token != 0
	tried := true
	if !DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
		return false
	si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)	; GdiplusStartupInput
	NumPut("UInt", 1, si)						; GdiplusVersion
	tok := 0
	if (DllCall("gdiplus\GdiplusStartup", "UPtr*", &tok, "Ptr", si, "Ptr", 0, "Int") = 0)
		token := tok
	return token != 0
}

; Existing file for an image reference, or "". Relative paths start at baseDir,
; then each of imageDirs (so ![[photo.jpg]] can live in an attachments folder).
MdResolveImage(src) {
	opts := MdOpts()
	rel := RegExReplace(MdUrlDecode(src), "[?#].*$")
	rel := StrReplace(rel, "/", "\")
	if (rel = "")
		return ""
	if RegExMatch(rel, "^(?:[A-Za-z]:\\|\\\\)")		; drive-letter or UNC path
		return MdIsFile(rel) ? rel : ""
	rel := LTrim(rel, "\")
	dirs := [opts["baseDir"]]
	for _, d in opts["imageDirs"]
		dirs.Push(d)
	for _, d in dirs {
		p := d "\" rel
		if MdIsFile(p)
			return p
	}
	return ""
}

MdIsFile(path) {
	attr := FileExist(path)
	return (attr != "" && !InStr(attr, "D"))
}

; Decode %XX escapes (runs of them are decoded together, as UTF-8 bytes).
MdUrlDecode(s) {
	if !InStr(s, "%")
		return s
	out := ""
	pos := 1
	while (found := RegExMatch(s, "(?:%[0-9A-Fa-f]{2})+", &m, pos)) {
		out .= SubStr(s, pos, found - pos)
		count := StrLen(m[0]) // 3
		bytes := Buffer(count, 0)
		loop count
			NumPut("UChar", Integer("0x" . SubStr(m[0], (A_Index - 1) * 3 + 2, 2)), bytes, A_Index - 1)
		out .= StrGet(bytes, count, "UTF-8")
		pos := found + StrLen(m[0])
	}
	return out . SubStr(s, pos)
}

; Value of an attribute in an HTML tag: src="x", src='x' or src=x. "" if absent.
MdAttr(tag, name) {
	if RegExMatch(tag, "i)\s" . name . "\s*=\s*(?:`"([^`"]*)`"|'([^']*)'|([^\s>]+))", &m) {
		if (m[1] != "")
			return m[1]
		if (m[2] != "")
			return m[2]
		return m[3]
	}
	return ""
}

MdBE16(buf, off) {
	return (NumGet(buf, off, "UChar") << 8) | NumGet(buf, off + 1, "UChar")
}

MdBE32(buf, off) {
	return (NumGet(buf, off, "UChar") << 24) | (NumGet(buf, off + 1, "UChar") << 16)
		| (NumGet(buf, off + 2, "UChar") << 8) | NumGet(buf, off + 3, "UChar")
}

; Pixel size of a JPEG: walks the marker segments up to the first frame header (SOFn).
MdJpegSize(buf, &w, &h) {
	n := buf.Size
	i := 2		; 0-based offset just past the SOI marker
	while (i + 4 <= n) {
		if (NumGet(buf, i, "UChar") != 0xFF) {
			i++
			continue
		}
		m := NumGet(buf, i + 1, "UChar")
		if (m = 0xFF) {		; fill byte
			i++
			continue
		}
		if (m = 0x00 || m = 0x01 || (m >= 0xD0 && m <= 0xD8)) {	; markers that carry no length
			i += 2
			continue
		}
		if (m = 0xD9)		; end of image before any frame header
			break
		if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
			if (i + 9 > n)
				break
			h := MdBE16(buf, i + 5)
			w := MdBE16(buf, i + 7)
			return true
		}
		i += 2 + MdBE16(buf, i + 2)
	}
	return false
}

; Hex text of a Buffer, no separators (Windows' own encoder - fast even for megabytes).
MdHexOf(buf) {
	flags := 0x4000000C		; CRYPT_STRING_HEXRAW | CRYPT_STRING_NOCRLF
	chars := 0
	if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", flags, "Ptr", 0, "UInt*", &chars, "Int")
		return ""
	out := Buffer(chars * 2, 0)
	if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", flags, "Ptr", out, "UInt*", &chars, "Int")
		return ""
	return StrGet(out, chars, "UTF-16")
}
