import cssparser.tokenizer;

import std.stdio;

void main()
{
    const cssStr = "p#id { color : #ff3300 }";

    foreach (token; new Tokenizer(cssStr))
    {
        token.writeln;
    }
}
