"""Rewrite comma-chained `let a = x, b = y;` groups in dialect/TimbdaRules.td
into one `let` statement per field: TableGen (the pinned vintage included) does
not accept multiple assignments in a single `let` - no upstream .td file uses
that form.  Splitting is depth-aware, so list literals (`["a", "b"]`) and commas
inside quoted paper text stay intact.

Run: python3 tools/split-lets.py dialect/TimbdaRules.td"""
import re
import sys


def split_top(s):
    """Split an assignment list on commas at bracket/quote depth 0."""
    parts, cur, depth, q = [], '', 0, None
    i = 0
    while i < len(s):
        ch = s[i]
        if q:
            cur += ch
            if ch == '\\' and i + 1 < len(s):
                cur += s[i + 1]
                i += 2
                continue
            if ch == q:
                q = None
        elif ch in '"':
            q = ch
            cur += ch
        elif ch in '([{':
            depth += 1
            cur += ch
        elif ch in ')]}':
            depth -= 1
            cur += ch
        elif ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
        i += 1
    if cur.strip():
        parts.append(cur)
    return parts


def rewrite(src):
    out, i, n = [], 0, 0
    while i < len(src):
        m = re.compile(r'([ \t]*)let ').search(src, i)
        if not m:
            out.append(src[i:])
            break
        indent, pos = m.group(1), m.end() - 4
        # find the terminating ';' at depth 0, skipping strings/brackets
        j, depth, q, k = pos + 4, 0, None, pos + 4
        while j < len(src):
            ch = src[j]
            if q:
                if ch == '\\' and j + 1 < len(src):
                    j += 2
                    continue
                if ch == q:
                    q = None
            elif ch == '"':
                q = ch
            elif ch in '([{':
                depth += 1
            elif ch in ')]}':
                depth -= 1
            elif ch == ';' and depth == 0:
                break
            j += 1
        body = src[pos + 4:j]
        if ',' not in split_top_dummy(body):
            out.append(src[pos:j + 1])
            i = j + 1
            continue
        assigns = [a.strip() for a in split_top(body) if a.strip()]
        if not all(re.match(r'^[A-Za-z_][A-Za-z_0-9]*\s*=', a) for a in assigns):
            out.append(src[pos:j + 1])
            i = j + 1
            continue
        flat = ' '.join(' '.join(a.split()) for a in assigns)
        for a in assigns:
            one = ' '.join(a.split())
            out.append('%slet %s;\n' % (indent, one))
            n += 1
        i = j + 1
    return ''.join(out), n


def split_top_dummy(s):
    # a cheap pre-filter: does the body contain a top-level comma at all?
    return [p for p in split_top(s) if p.strip()]


if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'dialect/TimbdaRules.td'
    src = open(path).read()
    dst, n = rewrite(src)
    open(path, 'w').write(dst)
    print('split %d comma-chained let groups into single-field lets' % n)
