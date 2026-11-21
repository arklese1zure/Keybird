
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

;## Debug #######################################################################
DummyFunction(*) { ; Placeholder.
	ToolTip "Test"
	SetTimer () => ToolTip(), -500
	return
}