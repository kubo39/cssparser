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
  switch (token.tokenType) {
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
  switch (token.tokenType){
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

  this(in ref string input)
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
    while (true) {
      Token token = nextIncludingWhitespaceAndComments;
      if (token.tokenType != TokenType.Whitespace && token.tokenType != TokenType.Comment) {
        return token;
      }
    }
  }

  Token nextIncludingWhitespace()
  {
    while (true) {
      Token token = nextIncludingWhitespaceAndComments;
      if (token.tokenType != TokenType.Comment) {
        return token;
      }
    }
  }

  // Return the next token in the input.
  Token nextIncludingWhitespaceAndComments()
  {
    BlockType blockType = atStartOf;
    if (blockType != BlockType.None) {
      consumeUntilEndOfBlock(blockType);
    }
    Token token = tokenizer.nextToken;
    blockType = openingBlockType(token);
    if (blockType != BlockType.None) {
      atStartOf = blockType;
    }
    return token;
  }

  void consumeUntilEndOfBlock(BlockType blockType)
  {
    while (true) {
      Token token = tokenizer.nextToken;
      if (closingBlockType(token) == blockType) {
        return;
      }
      blockType = openingBlockType(token);
      if (blockType != BlockType.None) {
        return consumeUntilEndOfBlock(blockType);
      }
    }
  }
}


unittest
{
  const s = "foo bar\nbaz\r\n\n\"a\\\r\nb\"";
  auto parser = new Parser(s);
  assert(parser.currentSourceLocation == SourceLocation(1, 1));
  assert(parser.nextIncludingWhitespace == Token(TokenType.Ident, "foo"));
  assert(parser.currentSourceLocation == SourceLocation(1, 4));
  assert(parser.nextIncludingWhitespace == Token(TokenType.Whitespace, " "));
  assert(parser.currentSourceLocation == SourceLocation(1, 5));
  assert(parser.nextIncludingWhitespace == Token(TokenType.Ident, "bar"));
  assert(parser.currentSourceLocation == SourceLocation(1, 8));
  assert(parser.nextIncludingWhitespace == Token(TokenType.Whitespace, "\n"));
  assert(parser.currentSourceLocation == SourceLocation(2, 1));
  assert(parser.nextIncludingWhitespace == Token(TokenType.Ident, "baz"));
  assert(parser.currentSourceLocation == SourceLocation(2, 4));
  assert(parser.nextIncludingWhitespace == Token(TokenType.Whitespace, "\r\n\n"));
  assert(parser.currentSourceLocation == SourceLocation(4, 1));
  assert(parser.nextIncludingWhitespace == Token(TokenType.QuotedString, "ab"));
  assert(parser.currentSourceLocation == SourceLocation(5, 3));
  assert(parser.isEOF);
}


unittest
{
  const s = " { foo ; bar } baz;,";
  auto parser = new Parser(s);
  auto token = parser.next;
  assert(token.tokenType == TokenType.CurlyBracketBlock);
  assert(token.value == "{");

  token = parser.next;
  assert(token.tokenType == TokenType.Ident);
  assert(token.value == "bar");
}


// https://drafts.csswg.org/css-syntax/#typedef-eof-token
unittest
{
  const s = "";
  auto parser = new Parser(s);
  auto token = parser.next;
  assert(token.tokenType == TokenType.EOF);
  token = parser.next;
  assert(token.tokenType == TokenType.EOF);
}
