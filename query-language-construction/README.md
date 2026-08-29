# Query Language Construction

Communication between the developed system and the user takes place through a purpose-built, declarative query language. The language's construction is based on the algebra presented in the previous chapter. Just as, for relational systems, relational algebra forms the basis for the SQL language — in our case, the developed algebra forms the basis for the RQL query language.

RQL stands for _RetractorDB Query Language_. Its syntax is very similar to SQL syntax. Bear in mind, however, that the correct term here is a _False Friend_. That is, it looks like SQL, but has little in common with it.

Valid statements in RQL currently begin with a handful of keywords. The most recognizable is the command starting with the keyword SELECT, followed by a list of attributes in the form of algebraic expressions — an algebra based on real numbers.

Statements are written in a text file. Its extension is conventionally .rql, but any other extension will also be accepted and processed. An RQL text file contains a sequence of statements beginning with defined keywords.

The `#` character starts a comment only when it is the first non-whitespace character on a line. The whole line, including an indented one, is discarded before parsing. Inside a `FROM` expression, `#` always means interleave regardless of whitespace. An end-of-line comment starts with `//`; block comments use `/* ... */`.

The query language was implemented using the Antlr4 parser generator \[[5](../references.md#5)]. The RQL grammar is written down, defined, and after every modification is compiled into the language in which RetractorDB itself was built. Every statement in a query file that is not a comment is compiled, processed, and modifies the system's internal state. A statement may span multiple lines — line continuation is signaled with a `\` character at the end of the line.
