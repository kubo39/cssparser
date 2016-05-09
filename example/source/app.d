import cssparser;

import std.stdio;

void main()
{
    const cssStr = "p#id { color : #ff3300 }";

    foreach (token; new Parser(cssStr))
    {
        token.writeln;
    }
}
