// https://drafts.csswg.org/css-syntax/#tokenization

module cssparser.tokenizer;

import std.algorithm : startsWith, canFind;
import std.ascii : isASCII, isDigit;
import std.string : toLower;
import std.conv : to, parse;
import std.typecons : Tuple, tuple;
import std.math : pow;


class EOFError : Exception
{
  this(string message,
       string file =__FILE__,
       size_t line = __LINE__,
       Throwable next = null) @safe pure nothrow
  {
    super(message, file, line, next);
  }
}


enum TokenType
{
  Ident,
  AtKeyword,
  Hash,
  IDHash,
  QuotedString,
  UnquotedUrl,
  Delim,
  Number,
  Percentage,
  Dimension,
  Whitespace,
  Comment,
  Colon,
  Semicolon,
  Comma,
  IncludeMatch,
  DashMatch,
  PrefixMatch,
  SuffixMatch,
  SubstringMatch,
  Column,
  CDO,
  CDC,
  Function,
  ParenthesisBlock,
  SquareBracketBlock,
  CurlyBracketBlock,
  BadUrl,
  BadString,
  CloseParenthesis,
  CloseSquareBracket,
  CloseCurlyBracket,
}


struct Token
{
  TokenType tokenType;
  string value;
}


enum VarFunctions
{
  DontCare,
  LookingForThem,
  SeenAtLeastOne,
}


alias SourceLocation = Tuple!(ulong, "line", ulong, "column");


class Tokenizer
{
  const string input;
  ulong position;
  VarFunctions varFunctions;
  SourceLocation lastKnownLineBreak;

  this(in ref string _input)
  {
    input = _input;
    position = 0;
    varFunctions = VarFunctions.DontCare;
    lastKnownLineBreak = SourceLocation(1, 0);
  }

  void lookForVarFunctions()
  {
    varFunctions = VarFunctions.LookingForThem;
  }

  bool seenVarFunctions()
  {
    bool seen = varFunctions == VarFunctions.SeenAtLeastOne;
    varFunctions = VarFunctions.DontCare;
    return seen;
  }

  void reset(ulong newPosition)
  {
    position = newPosition;
  }

  SourceLocation currentSourceLocation()
  {
    return sourceLocation(position);
  }

  SourceLocation sourceLocation(ulong target)
  {
    ulong lineNumber, newPosition;

    ulong lastKnownLineNumber = lastKnownLineBreak[0];
    ulong positionAfterLastKnownLine = lastKnownLineBreak[1];

    if (target >= positionAfterLastKnownLine) {
      newPosition = positionAfterLastKnownLine;
      lineNumber = lastKnownLineNumber;
    }
    else {
      newPosition = 0;
      lineNumber = 1;
    }
    string source = input[newPosition .. target];

    while (true) {
      ulong found = source.canFind("\n", "\r", "\x0C");
      if (!found) {
        break;
      }

      // index search.
      ulong newLinePosition = (string arr, immutable(char)[] targets) {
        foreach (target; targets) {
          foreach(id, v; arr) {
            if(v == target) {
              return id;
            }
          }
        }
        assert(false);
      }(source, ['\n', '\r', '\x0C']);

      auto offset = newLinePosition;
      if (source[newLinePosition .. $].startsWith("\r\n")) {
        offset += 2;
      }
      else {
        offset++;
      }
      source = source[offset .. $];
      newPosition += offset;
      lineNumber++;
    }
    assert(newPosition <= target);
    lastKnownLineBreak = SourceLocation(lineNumber, newPosition);
    return SourceLocation(lineNumber, target - newPosition + 1);
  }

  bool isEOF()
  {
    return !hasAtLeast(0);
  }

  bool hasAtLeast(ulong n)
  {
    return position + n < input.length;
  }

  char charAt(ulong offset)
  {
    return input[position + offset];
  }

  char nextChar()
  {
    return charAt(0);
  }

  auto advance(ulong n)
  {
    position += n;
  }

  bool hasNewlineAt(ulong offset)
  {
    char c = charAt(offset);
    return position + offset < input.length && (c == '\n' || c == '\r');
  }

  bool isIdentStart()
  {
    if (!isEOF) {
      switch (nextChar) {
      case 'a': .. case 'z':
      case 'A': .. case 'Z':
      case '_':
      case '\0':
        return true;
      case '-':
        if (hasAtLeast(1)) {
          switch (charAt(1)) {
          case 'a': .. case 'z':
          case 'A': .. case 'Z':
          case '_':
          case '\0':
            return true;
          case '\\':
            return !hasNewlineAt(1);
          default: return false;
          }
        }
        return false;
      case '\\':
        return !hasNewlineAt(1);
      default:
        assert(false);
      }
    }
    return false;
  }

  bool startsWith(string needle)
  {
    return input[position .. $].startsWith(needle);
  }

  // Parse [+-]?\d*(\.\d+)?([eE][+-]?\d+)?
  Token consumeNumeric()
  {
    double sign;
    bool hasSign;
    char c = nextChar;
    switch (c) {
    case '+':
      hasSign = true;
      sign = 1.0;
      break;
    case '-':
      hasSign = true;
      sign = -1.0;
      break;
    default:
      hasSign = false;
      sign = 1.0;
      break;
    }

    if (hasSign) {
      advance(1);
    }

    double integralPart = 0.0;
    while (true) {
      auto digit = nextChar;
      if (isDigit(digit)) {
        integralPart = integralPart * 10.0 + digit.to!double;
        advance(1);
        if (isEOF) {
          break;
        }
      }
      else {
        break;
      }
    }

    bool isInteger = true;
    double fractionalPart = 0.0;

    if (hasAtLeast(1) && nextChar == '.') {
      if (isDigit(charAt(1))) {
        isInteger = false;
        advance(1);
        double factor = 0.1;
        while (true) {
          auto digit = nextChar;
          if (isDigit(digit)) {
            fractionalPart += digit.to!double * factor;
            factor *= 0.1;
            advance(1);
            if (isEOF) {
              break;
            }
          }
          else {
            break;
          }
        }
      }
    }
    auto value = sign * (integralPart + fractionalPart);

    if ((hasAtLeast(1)
         && (nextChar == 'e' || nextChar == 'E')
         && charAt(1).isDigit
          ) || (
            hasAtLeast(2)
            && (nextChar == 'e' || nextChar == 'E')
            && (charAt(1) == '+' || charAt(1) == '-')
            && charAt(2).isDigit
            )
      ) {
      isInteger = false;
      advance(1);

      switch (nextChar) {
      case '-':
        hasSign = true;
        sign = -1.0;
        break;
      case '+':
        hasSign = true;
        sign = 1.0;
        break;
      default:
        hasSign = false;
        sign = 1.0;
        break;
      }

      if (hasSign) {
        advance(1);
      }

      double exponent = 0.0;

      while (true) {
        auto digit = nextChar;
        if (isDigit(digit)) {
          exponent = exponent * 10.0 + digit.to!double;
          advance(1);
          if (isEOF) {
            break;
          }
        }
        else {
          break;
        }
      }
      value *= pow(10.0, sign * exponent);
    }

    int intVal = void;
    if (isInteger) {
      if (value >= int.max.to!double) {
        intVal = int.max;
      }
      else if (value <= int.min.to!double) {
        intVal = int.min;
      }
      else {
        intVal = value.to!int;
      }
    }

    if (!isEOF && nextChar == '%') {
      advance(1);
      return Token(TokenType.Percentage, ((value.to!float) / 100.0).to!string);
    }

    if (isIdentStart) {
      return Token(TokenType.Dimension, value.to!string);
    }
    else {
      return Token(TokenType.Number, value.to!string);
    }
  }

  Token consumeIdentLike()
  {
    string value = consumeName;
    if (!isEOF && nextChar == '(') {
      advance(1);
      if (value.toLower == "url") {
        return consumeUnquotedUrl;
      }
      if (varFunctions == VarFunctions.LookingForThem &&
          value.toLower == "var") {
        varFunctions = VarFunctions.SeenAtLeastOne;
      }
      return Token(TokenType.Function, value);
    }
    return Token(TokenType.Ident, value);
  }

  // https://drafts.csswg.org/css-syntax/#url-token-diagram
  Token consumeUnquotedUrl()
  {
    auto start = position;  //  'url' -> '[start] ...

    foreach (offset, c; input[start .. $]) {
      switch (c) {
      case ' ':  // consume whitespace.
      case '\t':
      case '\n':
      case '\r':
      case '\x0C':
        break;
      case '"':
      case '\'':
        return Token(TokenType.Function);
      case ')':  // End of url-token.
        advance(offset);
        return Token(TokenType.UnquotedUrl, input[start .. position]);
      default:
        advance(offset);
        return innerConsumeUnquotedUrl();
      }
    }
    position = input.length;
    return Token(TokenType.UnquotedUrl, input[start .. position]);
  }

  Token innerConsumeUnquotedUrl()
  {
    auto start = position;
    string s = void;
    while (true) {
      if (isEOF) {
        return Token(TokenType.UnquotedUrl, input[start .. position]);
      }
      char c = nextChar;
      switch (c) {
      case ' ':  // consume whitespace.
      case '\t':
      case '\n':
      case '\r':
      case '\x0C':
        auto value = input[start .. position];
        advance(1);
        return consumeUrlEnd(value);
      case ')':
        auto value = input[start .. position];
        advance(1);
        return Token(TokenType.UnquotedUrl, value);
      case '\x01': .. case '\x08':
      case '\x0B':
      case '\x0E': .. case '\x1F':
      case '\x7F':
      case '"':
      case '\'':
      case '(':
        advance(1);
        return consumeBadUrl;
      case '\\':
      case '\0':
        s = input[start .. position];
        goto L0;
      default:
        advance(1);
        break;
      }
    }

  L0:
    while (!isEOF) {
      char c = nextChar;
      advance(1);
      switch (c) {
      case ' ':  // consume whitespace.
      case '\t':
      case '\n':
      case '\r':
      case '\x0C':
        return consumeUrlEnd(s);
      case ')':
        return Token(TokenType.UnquotedUrl, s);
      case '\x01': .. case '\x08':
      case '\x0B':
      case '\x0E': .. case '\x1F':
      case '\x7F':
      case '"':
      case '\'':
      case '(':
        return consumeBadUrl();
      case '\\':
        if (hasNewlineAt(0)) {
          return consumeBadUrl;
        }
        assert(false);
      case '\0':
        s ~= '\uFFFD';
        break;
      default:
        s ~= c;
      }
    }
    return Token(TokenType.UnquotedUrl, s);
  }

  Token consumeUrlEnd(string s)
  {
    while (!isEOF) {
      char c = nextChar;
      advance(1);
      switch (c) {
      case ' ':  // consume whitespace.
      case '\t':
      case '\n':
      case '\r':
      case '\x0C':
        break;
      case ')':
        return Token(TokenType.UnquotedUrl, s);
      default:
        return consumeBadUrl();
      }
    }
    return Token(TokenType.UnquotedUrl, s);
  }

  Token consumeBadUrl()
  {
    while (!isEOF) {
      char c = nextChar;
      advance(1);
      switch (c) {
      case ')':
        return Token(TokenType.BadUrl);
      case '\\':
        advance(1);
        break;
      default:
        break;
      }
    }
    return Token(TokenType.BadUrl);
  }

  string consumeName()
  {
    auto start = position;
    string value = void;

    while (true) {
      if (isEOF) {
        return input[start .. position];
      }
      char c = nextChar;
      switch (c) {
      case 'a': .. case 'z':
      case 'A': .. case 'Z':
      case '0': .. case '9':
      case '_':
      case '-':
        advance(1);
        break;
      case '\\':
      case '\0':
        value = input[start .. position];
        goto L0;
      default:
        if (c.isASCII) {
          return input[start .. position];
        }
        advance(1);
        break;
      }
    }
  L0:
    while (!isEOF) {
      char c = nextChar;
      switch (c) {
      case 'a': .. case 'z':
      case 'A': .. case 'Z':
      case '0': .. case '9':
      case '_':
      case '-':
        advance(1);
        value ~= c;
        break;
      case '\\':
        if (hasNewlineAt(1)) {
          return value;
        }
        advance(1);
        break;
      case '\0':
        advance(1);
        value ~= '\uFFFD';
        break;
      default:
        if (c.isASCII) {
          return value;
        }
        advance(1);
        break;
      }
    }
    return value;
  }

  Token consumeQuotedString(bool singleQuote)
  {
    advance(1);  // Skip initial quote.
    auto start = position;
    string ret;
    while (true) {
      if (isEOF) {
        return Token(TokenType.QuotedString, input[start .. $]);
      }
      switch (nextChar) {
      case '"':
        if (!singleQuote) {
          ret = input[start .. position];
          advance(1);
          return Token(TokenType.QuotedString, ret);
        }
        advance(1);
        goto L0;
      case '\'':
        if (singleQuote) {
          ret = input[start .. position];
          advance(1);
          return Token(TokenType.QuotedString, ret);
        }
        advance(1);
        goto L0;
      case '\\':
      case '\0':
        ret = input[start .. position];
        goto L0;
      case '\n':
      case '\r':
      case '\x0C':
        return Token(TokenType.BadString, ret);
      default:
        advance(1);
        break;
      }
    }
  L0:
    while (!isEOF) {
      char c = nextChar;
      if (c == '\n' || c == '\r' || c == '\x0C') {
        return Token(TokenType.BadString);
      }
      c = nextChar;
      advance(1);
      switch (c) {
      case '"':
        if (!singleQuote) {
          return Token(TokenType.QuotedString, ret);
        }
        break;
      case '\'':
        if (singleQuote) {
          return Token(TokenType.QuotedString, ret);
        }
        break;
      case '\\':
        if (!isEOF) {
          c = nextChar;
          switch (c) {
          case '\n':
          case '\x0C':
            advance(1);
            break;
          case '\r':
            advance(1);
            if (!isEOF && '\n' == nextChar) {
              advance(1);
            }
            break;
          default:
            ret ~= c;
            break;
          }
        }
        break;
      case '\0':
      default:
        ret ~= c;
        break;
      }
    }
    return Token(TokenType.QuotedString, ret);
  }

  Token nextToken()
  {
    if (isEOF) {
      throw new EOFError("reached end-of-file.");
    }
    char c = nextChar;

    switch (c) {
    case '\t':
    case '\n':
    case ' ':
    case '\r':
    case '\x0C':
      auto start = position;
      advance(1);
      while (!isEOF) {
        switch (nextChar) {
        case '\t':
        case '\n':
        case ' ':
        case '\r':
        case '\x0C':
          advance(1);
          break;
        default:
          goto L1;
        }
      }
    L1:
      return Token(TokenType.Whitespace, input[start .. position]);
    case '"':
      return consumeQuotedString(false);
    case '#':
      auto start = position;
      advance(1);
      if (isIdentStart) {
        return Token(TokenType.IDHash, "#");
      }
      else if (!isEOF) {
        switch (nextChar) {
        case 'a': .. case 'z':
        case 'A': .. case 'Z':
        case '0': .. case '9':
        case '-':
        case '_':
          return Token(TokenType.Hash, input[start .. position]);
        case '\\':
          if (!hasNewlineAt(1)) {
            return Token(TokenType.Hash, input[start .. position]);
          }
          goto default;
        default:
          return Token(TokenType.Delim, input[start .. position]);
        }
      }
      else {
        return Token(TokenType.Delim, "#");
      }
    case '$':
      if (startsWith("$=")) {
        advance(2);
        return Token(TokenType.SuffixMatch, "$=");
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "$");
      }
    case '\'':
      return consumeQuotedString(true);
    case '(':
      advance(1);
      return Token(TokenType.ParenthesisBlock, "(");
    case ')':
      advance(1);
      return Token(TokenType.CloseParenthesis, ")");
    case '*':
      if (startsWith("*=")) {
        advance(2);
        return Token(TokenType.SubstringMatch, "*=");
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "*");
      }
    case '+':
      if ((hasAtLeast(1)
           && isDigit(charAt(1))
            ) || (
              hasAtLeast(2)
              && (charAt(1) == '.')
              && isDigit(charAt(2)))) {
        return consumeNumeric;
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "+");
      }
    case ',':
      advance(1);
      return Token(TokenType.Comma, ",");
    case '-':
      if ((hasAtLeast(1)
          && isDigit(charAt(1))
            ) || (
              hasAtLeast(2)
              && (charAt(1) == '.')
              && isDigit(charAt(2)))) {
        return consumeNumeric;
      }
      else if (startsWith("-->")) {
        advance(3);
        return Token(TokenType.CDC, "-->");
      }
      else if (isIdentStart) {
        return consumeIdentLike;
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "-");
      }
    case '.':
      if (hasAtLeast(1) && isDigit(charAt(1))) {
        return consumeNumeric;
      }
      else {
        advance(1);
        return Token(TokenType.Delim, ".");
      }
    case '/':
      if (startsWith("/*")) {
        advance(2);
        auto start = position;
        string content = void;
        auto found = input[position .. $].canFind("*/");
        if (!found) {
          position = input.length;
          content = input[start .. position];
        }
        else {
          advance(found);
          content = input[start .. position];
          advance(2);
        }
        return Token(TokenType.Comment, content);
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "/");
      }
    case '0': .. case '9':
      return consumeNumeric;
    case ':':
      advance(1);
      return Token(TokenType.Colon, ":");
    case ';':
      advance(1);
      return Token(TokenType.Semicolon, ";");
    case '<':
      if (startsWith("<!--")) {
        advance(4);
        return Token(TokenType.CDO, "<!--");
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "<");
      }
    case '@':
      advance(1);
      if (isIdentStart()) {
        return Token(TokenType.AtKeyword, "@");
      }
      else {
        return Token(TokenType.Delim, "@");
      }
    case 'a': .. case 'z':
    case 'A': .. case 'Z':
    case '_':
    case '\0':
      return consumeIdentLike;
    case '[':
      advance(1);
      return Token(TokenType.SquareBracketBlock, "[");
    case '\\':
      if (!hasNewlineAt(1)) {
        return consumeIdentLike;
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "[");
      }
    case ']':
      advance(1);
      return Token(TokenType.CloseSquareBracket, "]");
    case '^':
      if (startsWith("^=")) {
        advance(2);
        return Token(TokenType.PrefixMatch, "^=");
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "^");
      }
    case '{':
      advance(1);
      return Token(TokenType.CurlyBracketBlock, "{");
    case '|':
      if (startsWith("|=")) {
        advance(2);
        return Token(TokenType.DashMatch, "|=");
      }
      else if (startsWith("||")) {
        advance(2);
        return Token(TokenType.Column, "||");
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "|");
      }
    case '}':
      advance(1);
      return Token(TokenType.CloseCurlyBracket, "}");
    case '~':
      if (startsWith("~=")) {
        advance(2);
        return Token(TokenType.IncludeMatch, "~=");
      }
      else {
        advance(1);
        return Token(TokenType.Delim, "~");
      }
    default:
      advance(1);
      return Token(TokenType.Delim, c.to!string);
    }
    assert(false);
  }
}


unittest
{
  const s = "foo:";
  auto tokenizer = new Tokenizer(s);

  Token token = tokenizer.nextToken;
  assert(token.tokenType == TokenType.Ident);
  assert(token.value == "foo");

  token = tokenizer.nextToken;
  assert(token.tokenType == TokenType.Colon);
  assert(token.value == ":");

  assert(tokenizer.isEOF);
}
