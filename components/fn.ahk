
;		=========================================================================
;		|||||					Common functions							|||||
;		=========================================================================

;## Arrays ######################################################################
ArrayContains(arr, needle) { ; Look up simple strings in an array.
    for _, val in arr
        if (val = needle) ; If element exists, true is returned.
            return true
    return false
}

SortedArray(arr) { ; Sort array alphabetically.
	if !arr.Length
		return []
	joined := ""
	for _, v in arr
		joined .= v "`n"
	return StrSplit(Sort(RTrim(joined, "`n")), "`n")
}

;## Strings #####################################################################
StrJoin(sep, items*) { ; Join values with a separator, e.g. StrJoin(", ", arr*) -> "a, b, c".
	out := ""
	for i, item in items
		out .= (i > 1 ? sep : "") item
	return out
}

RemoveAccents(text) { ; Remove accentuated characters from any string.
    static replacements := [ ; Static ensures the array is only built once. For improving performance.
        ["[áàâäãå]", "a"], ["[ÁÀÂÄÃÅ]", "A"],
        ["[éèêë]", "e"], ["[ÉÈÊË]", "E"],
        ["[íìîï]", "i"], ["[ÍÌÎÏ]", "I"],
        ["[óòôöõø]", "o"], ["[ÓÒÔÖÕØ]", "O"],
        ["[úùûü]", "u"], ["[ÚÙÛÜ]", "U"],
        ["[ýÿ]", "y"], ["[ÝŸ]", "Y"],
        ["[ç]", "c"], ["[Ç]", "C"],
        ["[ñ]", "n"], ["[Ñ]", "N"]
    ]
    for _, pair in replacements { ; Loop through each pair and replace the matches
        text := RegExReplace(text, pair[1], pair[2])
    }
    return text
}

;## Versions ####################################################################
CompareVersions(a, b) { ; Compare version strings. Returns 1 if a is newer, -1 if b is newer, 0 if equal.
	; "v1.2.10" vs "1.3" -> -1. A leading "v" and any "-beta"/"+build" suffix are ignored.
	; Missing parts count as 0, so "1.2" = "1.2.0". Parts are compared as numbers, so 0.10 > 0.9.
	pa := VersionParts(a), pb := VersionParts(b)
	loop Max(pa.Length, pb.Length) {
		x := A_Index <= pa.Length ? pa[A_Index] : 0
		y := A_Index <= pb.Length ? pb[A_Index] : 0
		if x != y
			return x > y ? 1 : -1
	}
	return 0
}

VersionParts(version) { ; "v1.2.3-beta" -> [1, 2, 3]. Non-numeric parts count as 0.
	version := RegExReplace(Trim(version), "i)^v")
	version := RegExReplace(version, "[-+].*$")
	parts := []
	for _, part in StrSplit(version, ".")
		parts.Push(IsInteger(part) ? Integer(part) : 0)
	return parts
}

;## Debug #######################################################################
DummyFunction(*) { ; Placeholder.
	ToolTip "Test"
	SetTimer () => ToolTip(), -500
	return
}