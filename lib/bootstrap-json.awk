# Narrow JSON field reader for bootstrap metadata before envpilot-core exists.
# Reads root release ID/tag, or an attachment ID by its ASCII release filename.
# Values are never evaluated as shell code. YAML always uses envpilot-core.
BEGIN { RS = "\0"; ORS = ""; depth = 0 }
{
    text = $0
    for (i = 1; i <= length(text); i++) {
        ch = substr(text, i, 1)
        if (ch == "\"") {
            value = ""
            for (i++; i <= length(text); i++) {
                ch = substr(text, i, 1)
                if (ch == "\\") {
                    i++
                    escaped = substr(text, i, 1)
                    if (escaped == "\"" || escaped == "\\" || escaped == "/") value = value escaped
                    else value = value "\\" escaped
                } else if (ch == "\"") break
                else value = value ch
            }
            nextpos = i + 1
            while (substr(text, nextpos, 1) ~ /[ \t\r\n]/) nextpos++
            if (substr(text, nextpos, 1) == ":") key[depth] = value
            else {
                if (key[depth] == "name") names[depth] = value
                if (mode == "tag" && depth == 1 && key[depth] == "tag_name") { print value; exit }
            }
        } else if (ch == "{" || ch == "[") {
            depth++
            key[depth] = ""; names[depth] = ""; ids[depth] = ""
        } else if (ch == "}" || ch == "]") {
            if (mode == "asset" && ch == "}" && depth == 2 && names[depth] == wanted && ids[depth] != "") {
                print ids[depth]; exit
            }
            depth--
        } else if (ch ~ /[0-9]/) {
            value = ch
            while (substr(text, i + 1, 1) ~ /[0-9]/) { i++; value = value substr(text, i, 1) }
            if (key[depth] == "id") {
                ids[depth] = value
                if (mode == "release" && depth == 1) { print value; exit }
            }
        }
    }
}
