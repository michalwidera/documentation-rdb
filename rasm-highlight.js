(function () {
    "use strict";

    if (typeof window.hljs === "undefined") {
        return;
    }

    window.hljs.registerLanguage("rasm", function () {
        const number = {
            className: "number",
            variants: [
                { begin: /\b\d+\/\d+\b/ },
                { begin: /(?:\b\d+(?:\.\d*)?|\B\.\d+)(?:E[+-]?\d+)?\b/i },
            ],
            relevance: 0,
        };

        return {
            name: "RQL Assembler",
            aliases: ["rql-assembler"],
            keywords: {
                keyword:
                    "VOID_COMMAND VOID_VALUE PUSH_ID PUSH_ID1 PUSH_ID2 PUSH_ID3 PUSH_ID4 PUSH_ID5 " +
                    "PUSH_IDX PUSH_VAL PUSH_TSCAN TYPE ADD SUBTRACT MULTIPLY DIVIDE NEGATE AND OR NOT " +
                    "CMP_EQUAL CMP_LT CMP_GT CMP_LE CMP_GE CMP_NOT_EQUAL STREAM_AVG STREAM_MIN STREAM_MAX " +
                    "STREAM_SUM CALL CALL2 PUSH_STREAM STREAM_HASH STREAM_DEHASH_DIV STREAM_DEHASH_MOD " +
                    "STREAM_ADD STREAM_SUBTRACT STREAM_TIMEMOVE STREAM_AGSE COUNT COUNT_RANGE PUSH_GENIDX " +
                    "POWER WINDOW_MIN WINDOW_MAX WINDOW_AVG WINDOW_SUM WINDOW RULE DO DUMP TO RETENTION SYSTEM rows",
                type: "BYTE INTEGER UINT RATIONAL FLOAT DOUBLE INTPAIR IDXPAIR STRING NULLTYPE REF RETMEMORY TYP",
                literal: "NULL null",
            },
            contains: [
                {
                    className: "comment",
                    begin: /\b(?:tail|origin)=\d+\b/,
                    relevance: 0,
                },
                {
                    className: "string",
                    begin: /(?:^|[\t ])[A-Za-z0-9_./$-]+\.(?:txt|dat|bin|rdb|desc|meta)\b/,
                    relevance: 0,
                },
                {
                    className: "variable",
                    begin: /^[A-Za-z_][A-Za-z0-9_$]*(?=\((?:\d+\/\d+|delta)\))/,
                    relevance: 0,
                },
                {
                    begin: /\b(?:PUSH_STREAM|PUSH_ID)\(/,
                    end: /\)/,
                    excludeBegin: true,
                    excludeEnd: true,
                    contains: [
                        {
                            className: "variable",
                            begin: /[A-Za-z_][A-Za-z0-9_$]*/,
                            relevance: 0,
                        },
                        number,
                    ],
                },
                number,
            ],
        };
    });

    document.querySelectorAll("pre code.language-rasm").forEach(function (block) {
        block.removeAttribute("data-highlighted");
        if (typeof window.hljs.highlightElement === "function") {
            window.hljs.highlightElement(block);
        } else {
            window.hljs.highlightBlock(block);
        }
    });
})();
