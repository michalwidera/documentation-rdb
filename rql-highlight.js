(function () {
    "use strict";

    if (typeof window.hljs === "undefined") {
        return;
    }

    window.hljs.registerLanguage("rql", function () {
        const blockComment = {
            className: "comment",
            begin: /\/\*/,
            end: /\*\//,
            contains: ["self"],
        };

        return {
            name: "RetractorQL",
            aliases: ["rql"],
            keywords: {
                keyword:
                    "SELECT select STREAM stream FROM from DECLARE declare RETENTION retention " +
                    "FILE file STORAGE storage ROTATION rotation SUBSTRAT substrat RULE rule " +
                    "DISPOSABLE disposable ONESHOT oneshot HOLD hold VOLATILE volatile " +
                    "PERSISTENT persistent DEFAULT default ON on WHEN when DUMP dump SYSTEM system DO do TO to " +
                    "AND and OR or NOT not",
                type: "BYTE Byte CHAR Char STRING String UINT Uint INTEGER Integer FLOAT Float DOUBLE Double",
                literal:
                    "MEMORY memory DIRECT direct POSIX posix POSIXSHD posixshd " +
                    "GENERIC generic DEVICE device TEXTSOURCE textsource",
                built_in: "MIN min MAX max AVG avg SUMC sumc",
            },
            contains: [
                {
                    className: "comment",
                    begin: /^[ \t]*#/,
                    end: /$/,
                },
                {
                    className: "comment",
                    begin: /\/\//,
                    end: /$/,
                },
                blockComment,
                {
                    className: "string",
                    begin: /'/,
                    end: /'/,
                    contains: [
                        {
                            className: "char.escape",
                            begin: /''/,
                            relevance: 0,
                        },
                    ],
                },
                {
                    className: "built_in",
                    begin:
                        /\b(?:sqrt|ceil|floor|abs|round|trunc|sin|cos|exp|tan|log2|log|isnull|null2zero|iszero|isnonzero|length|to_integer|to_float|to_double|to_string|int|real|str)\b(?=\s*\()/i,
                },
                {
                    className: "built_in",
                    begin: /\bfloat\b(?=\s*\()/,
                },
                {
                    className: "number",
                    variants: [
                        { begin: /\b\d+\/\d+\b/ },
                        { begin: /(?:\b\d+(?:\.\d*)?|\B\.\d+)E[+-]?\d+\b/ },
                        { begin: /(?:\b\d+\.\d*|\B\.\d+)/ },
                        { begin: /\b\d+\b/ },
                    ],
                    relevance: 0,
                },
                {
                    className: "keyword",
                    begin: /(?:!=|>=|<=|\|\||::|[=<>!#&%@+$:*/~^|-])/,
                    relevance: 0,
                },
            ],
        };
    });

    document.querySelectorAll("pre code.language-rql").forEach(function (block) {
        block.removeAttribute("data-highlighted");
        if (typeof window.hljs.highlightElement === "function") {
            window.hljs.highlightElement(block);
        } else {
            window.hljs.highlightBlock(block);
        }
    });
})();
