(function () {
    "use strict";

    if (typeof window.hljs === "undefined") {
        return;
    }

    window.hljs.registerLanguage("desc", function () {
        const blockComment = {
            className: "comment",
            begin: /\/\*/,
            end: /\*\//,
            contains: ["self"],
        };

        return {
            name: "RetractorDB Descriptor",
            aliases: ["rdb-desc", "rdbdesc"],
            keywords: {
                keyword: "REF TYPE RETENTION RETMEMORY",
                type: "BYTE STRING UINT INTEGER FLOAT DOUBLE RATIONAL",
                literal: "DEFAULT MEMORY DIRECT POSIX POSIXSHD GENERIC DEVICE TEXTSOURCE",
            },
            contains: [
                {
                    className: "string",
                    begin: /"/,
                    end: /"/,
                },
                blockComment,
                {
                    className: "comment",
                    begin: /# /,
                    end: /$/,
                },
                {
                    className: "comment",
                    begin: /\/\//,
                    end: /$/,
                },
                {
                    className: "number",
                    begin: /\b\d+\b/,
                    relevance: 0,
                },
                {
                    className: "keyword",
                    begin: /[{}\[\]]/,
                    relevance: 0,
                },
            ],
        };
    });

    document.querySelectorAll("pre code.language-desc").forEach(function (block) {
        block.removeAttribute("data-highlighted");
        if (typeof window.hljs.highlightElement === "function") {
            window.hljs.highlightElement(block);
        } else {
            window.hljs.highlightBlock(block);
        }
    });
})();
