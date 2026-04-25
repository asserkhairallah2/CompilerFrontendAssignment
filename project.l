%option noyywrap yylineno

%{
typedef struct Node Node;
typedef struct StmtList StmtList;
#include "project.tab.h"
#include <stdlib.h>
#include <string.h>
%}

%%
[ \t\r]+                  ;
"//"[^\n]*               ;

"print"                   { return PRINT; }
"if"                      { return IF; }
"while"                   { return WHILE; }

">="                      { return GE; }
"<="                      { return LE; }
"=="                      { return EQ; }
"!="                      { return NE; }

[0-9]+                    { yylval.ival = atoi(yytext); return NUMBER; }
[a-zA-Z_][a-zA-Z0-9_]*    { yylval.sval = strdup(yytext); return IDENTIFIER; }

\n                        { return NEWLINE; }
.                         { return yytext[0]; }
%%
