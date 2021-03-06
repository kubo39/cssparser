module cssparser.parser;

import cssparser.tokenizer;


enum BlockType
{
    None,
    Parenthesis,
    SquareBracket,
    CurlyBracket,
}


BlockType openingBlockType(Token token)
{
    switch (token.type)
    {
    case TokenType.ParenthesisBlock:
        return BlockType.Parenthesis;
    case TokenType.SquareBracketBlock:
        return BlockType.SquareBracket;
    case TokenType.CurlyBracketBlock:
        return BlockType.CurlyBracket;
    default:
        return BlockType.None;
    }
    assert(false);
}


BlockType closingBlockType(Token token)
{
    switch (token.type)
    {
    case TokenType.CloseParenthesis:
        return BlockType.Parenthesis;
    case TokenType.CloseSquareBracket:
        return BlockType.SquareBracket;
    case TokenType.CloseCurlyBracket:
        return BlockType.CurlyBracket;
    default:
        return BlockType.None;
    }
    assert(false);
}


class Parser
{
    Tokenizer tokenizer;
    BlockType atStartOf;

    this(in string input)
    {
        tokenizer = new Tokenizer(input);
        atStartOf = BlockType.None;
    }

    bool isEOF()
    {
        return tokenizer.isEOF;
    }

    SourceLocation currentSourceLocation()
    {
        return tokenizer.currentSourceLocation;
    }

    SourceLocation sourceLocation(ulong target)
    {
        return tokenizer.sourceLocation(target);
    }

    // Return the next token in the input that is neither whitespace or a comment.
    Token next()
    {
        while (true)
        {
            Token token = nextIncludingWhitespaceAndComments;
            if (token.type != TokenType.Whitespace && token.type != TokenType.Comment)
                return token;
        }
    }

    Token nextIncludingWhitespace()
    {
        while (true)
        {
            Token token = nextIncludingWhitespaceAndComments;
            if (token.type != TokenType.Comment)
                return token;
        }
    }

    // Return the next token in the input.
    Token nextIncludingWhitespaceAndComments()
    {
        BlockType blockType = atStartOf;
        if (blockType != BlockType.None)
            consumeUntilEndOfBlock(blockType);
        Token token = tokenizer.nextToken;
        blockType = openingBlockType(token);
        if (blockType != BlockType.None)
            atStartOf = blockType;
        return token;
    }

    void consumeUntilEndOfBlock(BlockType blockType)
    {
        while (true)
        {
            Token token = tokenizer.nextToken;
            if (closingBlockType(token) == blockType)
                return;
            blockType = openingBlockType(token);
            if (blockType != BlockType.None)
                return consumeUntilEndOfBlock(blockType);
        }
    }

    class Range
    {
        Parser _parser;
        Token current;

        this(Parser parser)
        {
            _parser = parser;
            current = _parser.next;  // first time.
        }

        bool empty()
        {
            return current.type == TokenType.EOF;
        }

        Token front()
        {
            return current;
        }

        void popFront()
        {
            current = _parser.next;
        }
    }

    unittest
    {
        import std.range : isInputRange;
        static assert (isInputRange!Range);
    }

    Range opSlice()
    {
        return new Range(this);
    }
}


unittest
{
    const s = "foo bar\nbaz\r\n\n\"a\\\r\nb\"";
    auto parser = new Parser(s);
    assert(parser.currentSourceLocation == SourceLocation(1, 1));
    assert(parser.nextIncludingWhitespace == Token(TokenType.Ident, "foo"));
    assert(parser.currentSourceLocation == SourceLocation(1, 4));
    assert(parser.nextIncludingWhitespace == Token(TokenType.Whitespace));
    assert(parser.currentSourceLocation == SourceLocation(1, 5));
    assert(parser.nextIncludingWhitespace == Token(TokenType.Ident, "bar"));
    assert(parser.currentSourceLocation == SourceLocation(1, 8));
    assert(parser.nextIncludingWhitespace == Token(TokenType.Whitespace));
    assert(parser.currentSourceLocation == SourceLocation(2, 1));
    assert(parser.nextIncludingWhitespace == Token(TokenType.Ident, "baz"));
    assert(parser.currentSourceLocation == SourceLocation(2, 4));
    assert(parser.nextIncludingWhitespace == Token(TokenType.Whitespace));
    assert(parser.currentSourceLocation == SourceLocation(4, 1));
    assert(parser.nextIncludingWhitespace == Token(TokenType.QuotedString, "ab"));
    assert(parser.currentSourceLocation == SourceLocation(5, 3));
    assert(parser.isEOF);
}


unittest
{
    const s = "url()";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token.type == TokenType.UnquotedUrl);
    assert(token.value == "");
}


unittest
{
    const s = "url( abc";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token.type == TokenType.UnquotedUrl);
    assert(token.value == "abc");
}


unittest
{
    const s = "url( abc \t";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token.type == TokenType.UnquotedUrl);
    assert(token.value == "abc");
}


// https://drafts.csswg.org/css-syntax/#typedef-url-token
unittest
{
    const s = "url( abc (";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token.type == TokenType.BadUrl);
}


unittest
{
    const s = "url( abc )";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token == Token(TokenType.UnquotedUrl, "abc"));
    assert(parser.isEOF);
}


unittest
{
    const s = " { foo ; bar } baz;,";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token.type == TokenType.CurlyBracketBlock);
    assert(token.value == "{");

    token = parser.next;
    assert(token.type == TokenType.Ident);
    assert(token.value == "bar");
}


// https://drafts.csswg.org/css-syntax/#typedef-eof-token
unittest
{
    const s = "";
    auto parser = new Parser(s);
    auto token = parser.next;
    assert(token.type == TokenType.EOF);
    token = parser.next;
    assert(token.type == TokenType.EOF);
}


// Range
unittest
{
    import std.conv : to;

    const s = "bar";
    Token last;
    foreach (token; new Parser(s))
    {
        last = token;
    }
    assert(last.type == TokenType.Ident, last.type.to!string);
}
