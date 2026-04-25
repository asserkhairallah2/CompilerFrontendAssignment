%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

int yylex(void);
void yyerror(const char *s);
extern int yylineno;

typedef enum {
    NODE_NUMBER,
    NODE_VARIABLE,
    NODE_BINOP,
    NODE_UNARY,
    NODE_ASSIGN,
    NODE_PRINT,
    NODE_EXPR_STMT,
    NODE_IF,
    NODE_WHILE,
    NODE_BLOCK
} NodeType;

typedef enum {
    OP_ADD = '+',
    OP_SUB = '-',
    OP_MUL = '*',
    OP_DIV = '/',
    OP_GT = '>',
    OP_LT = '<',
    OP_GE = 1001,
    OP_LE,
    OP_EQ,
    OP_NE,
    OP_NEG
} OpType;

typedef struct Node Node;
typedef struct StmtList StmtList;

struct Node {
    NodeType type;
    union {
        int number;
        char *name;
        struct {
            OpType op;
            Node *left;
            Node *right;
        } binop;
        struct {
            OpType op;
            Node *expr;
        } unary;
        struct {
            char *name;
            Node *value;
        } assign;
        struct {
            Node *expr;
        } print_stmt;
        struct {
            Node *expr;
        } expr_stmt;
        struct {
            Node *cond;
            Node *body;
        } if_stmt;
        struct {
            Node *cond;
            Node *body;
        } while_stmt;
        struct {
            StmtList *statements;
        } block;
    } data;
};

struct StmtList {
    Node *stmt;
    StmtList *next;
};

typedef struct {
    char name[64];
    int value;
} Symbol;

#define MAX_SYMBOLS 128

static Symbol symbols[MAX_SYMBOLS];
static int symbol_count = 0;
static StmtList *program_statements = NULL;
static int semantic_error_count = 0;
static int syntax_error_count = 0;
static FILE *ir_file = NULL;
static int ir_temp_counter = 1;
static int ir_label_counter = 1;

static void report_semantic_error(const char *fmt, ...)
{
    va_list args;

    semantic_error_count++;
    fprintf(stderr, "Semantic error: ");

    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);

    fprintf(stderr, "\n");
}

static int validate_identifier_name(const char *name)
{
    size_t max_len = sizeof(symbols[0].name) - 1;
    if (strlen(name) > max_len) {
        report_semantic_error("identifier '%s' exceeds max length %zu", name, max_len);
        return 0;
    }
    return 1;
}

static char *copy_string(const char *src)
{
    char *out = (char *)malloc(strlen(src) + 1);
    if (out == NULL) {
        fprintf(stderr, "Out of memory\n");
        exit(1);
    }
    strcpy(out, src);
    return out;
}

static char *string_printf(const char *fmt, ...)
{
    int needed;
    va_list args;
    char *out;

    va_start(args, fmt);
    needed = vsnprintf(NULL, 0, fmt, args);
    va_end(args);

    if (needed < 0) {
        fprintf(stderr, "Internal error: failed to format string\n");
        exit(1);
    }

    out = (char *)malloc((size_t)needed + 1);
    if (out == NULL) {
        fprintf(stderr, "Out of memory\n");
        exit(1);
    }

    va_start(args, fmt);
    vsnprintf(out, (size_t)needed + 1, fmt, args);
    va_end(args);

    return out;
}

static Node *new_node(NodeType type)
{
    Node *node = (Node *)malloc(sizeof(Node));
    if (node == NULL) {
        fprintf(stderr, "Out of memory\n");
        exit(1);
    }
    node->type = type;
    return node;
}

static Node *make_number(int value)
{
    Node *node = new_node(NODE_NUMBER);
    node->data.number = value;
    return node;
}

static Node *make_variable(const char *name)
{
    Node *node = new_node(NODE_VARIABLE);
    node->data.name = copy_string(name);
    return node;
}

static Node *make_binop(OpType op, Node *left, Node *right)
{
    Node *node = new_node(NODE_BINOP);
    node->data.binop.op = op;
    node->data.binop.left = left;
    node->data.binop.right = right;
    return node;
}

static Node *make_unary(OpType op, Node *expr)
{
    Node *node = new_node(NODE_UNARY);
    node->data.unary.op = op;
    node->data.unary.expr = expr;
    return node;
}

static Node *make_assign(const char *name, Node *value)
{
    Node *node = new_node(NODE_ASSIGN);
    node->data.assign.name = copy_string(name);
    node->data.assign.value = value;
    return node;
}

static Node *make_print(Node *expr)
{
    Node *node = new_node(NODE_PRINT);
    node->data.print_stmt.expr = expr;
    return node;
}

static Node *make_expr_stmt(Node *expr)
{
    Node *node = new_node(NODE_EXPR_STMT);
    node->data.expr_stmt.expr = expr;
    return node;
}

static Node *make_if(Node *cond, Node *body)
{
    Node *node = new_node(NODE_IF);
    node->data.if_stmt.cond = cond;
    node->data.if_stmt.body = body;
    return node;
}

static Node *make_while(Node *cond, Node *body)
{
    Node *node = new_node(NODE_WHILE);
    node->data.while_stmt.cond = cond;
    node->data.while_stmt.body = body;
    return node;
}

static Node *make_block(StmtList *statements)
{
    Node *node = new_node(NODE_BLOCK);
    node->data.block.statements = statements;
    return node;
}

static StmtList *list_append(StmtList *list, Node *stmt)
{
    StmtList *item;
    StmtList *tail;

    if (stmt == NULL) {
        return list;
    }

    item = (StmtList *)malloc(sizeof(StmtList));
    if (item == NULL) {
        fprintf(stderr, "Out of memory\n");
        exit(1);
    }

    item->stmt = stmt;
    item->next = NULL;

    if (list == NULL) {
        return item;
    }

    tail = list;
    while (tail->next != NULL) {
        tail = tail->next;
    }
    tail->next = item;
    return list;
}

static StmtList *list_concat(StmtList *first, StmtList *second)
{
    StmtList *tail;

    if (first == NULL) {
        return second;
    }

    tail = first;
    while (tail->next != NULL) {
        tail = tail->next;
    }
    tail->next = second;
    return first;
}

static int find_symbol(const char *name)
{
    int i;
    for (i = 0; i < symbol_count; i++) {
        if (strcmp(symbols[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

static int get_symbol_value(const char *name)
{
    int idx = find_symbol(name);

    if (!validate_identifier_name(name)) {
        return 0;
    }

    if (idx < 0) {
        report_semantic_error("undefined variable '%s'", name);
        return 0;
    }
    return symbols[idx].value;
}

static void set_symbol_value(const char *name, int value)
{
    int idx = find_symbol(name);

    if (!validate_identifier_name(name)) {
        return;
    }

    if (idx >= 0) {
        symbols[idx].value = value;
        return;
    }

    if (symbol_count >= MAX_SYMBOLS) {
        report_semantic_error("symbol table overflow (max %d variables)", MAX_SYMBOLS);
        return;
    }

    strncpy(symbols[symbol_count].name, name, sizeof(symbols[symbol_count].name) - 1);
    symbols[symbol_count].name[sizeof(symbols[symbol_count].name) - 1] = '\0';
    symbols[symbol_count].value = value;
    symbol_count++;
}

static int eval_expr(Node *node)
{
    int left;
    int right;

    if (node == NULL) {
        return 0;
    }

    switch (node->type) {
    case NODE_NUMBER:
        return node->data.number;

    case NODE_VARIABLE:
        return get_symbol_value(node->data.name);

    case NODE_UNARY:
        if (node->data.unary.op == OP_NEG) {
            return -eval_expr(node->data.unary.expr);
        }
        break;

    case NODE_BINOP:
        left = eval_expr(node->data.binop.left);
        right = eval_expr(node->data.binop.right);

        switch (node->data.binop.op) {
        case OP_ADD:
            return left + right;
        case OP_SUB:
            return left - right;
        case OP_MUL:
            return left * right;
        case OP_DIV:
            if (right == 0) {
                report_semantic_error("division by zero");
                return 0;
            }
            return left / right;
        case OP_GT:
            return left > right;
        case OP_LT:
            return left < right;
        case OP_GE:
            return left >= right;
        case OP_LE:
            return left <= right;
        case OP_EQ:
            return left == right;
        case OP_NE:
            return left != right;
        default:
            break;
        }
        break;

    default:
        break;
    }

    fprintf(stderr, "Internal error: invalid expression node\n");
    return 0;
}

static const char *op_to_text(OpType op)
{
    switch (op) {
    case OP_ADD:
        return "+";
    case OP_SUB:
        return "-";
    case OP_MUL:
        return "*";
    case OP_DIV:
        return "/";
    case OP_GT:
        return ">";
    case OP_LT:
        return "<";
    case OP_GE:
        return ">=";
    case OP_LE:
        return "<=";
    case OP_EQ:
        return "==";
    case OP_NE:
        return "!=";
    default:
        return "?";
    }
}

static void emit_ir(const char *fmt, ...)
{
    va_list args;

    if (ir_file == NULL) {
        return;
    }

    va_start(args, fmt);
    vfprintf(ir_file, fmt, args);
    va_end(args);

    fprintf(ir_file, "\n");
}

static char *new_temp_name(void)
{
    return string_printf("t%d", ir_temp_counter++);
}

static char *new_label_name(void)
{
    return string_printf("L%d", ir_label_counter++);
}

static char *generate_expr_ir(Node *node)
{
    char *left;
    char *right;
    char *temp;

    if (node == NULL) {
        return copy_string("0");
    }

    switch (node->type) {
    case NODE_NUMBER:
        return string_printf("%d", node->data.number);

    case NODE_VARIABLE:
        return copy_string(node->data.name);

    case NODE_UNARY:
        if (node->data.unary.op == OP_NEG) {
            left = generate_expr_ir(node->data.unary.expr);
            temp = new_temp_name();
            emit_ir("%s = - %s", temp, left);
            free(left);
            return temp;
        }
        return copy_string("0");

    case NODE_BINOP:
        left = generate_expr_ir(node->data.binop.left);
        right = generate_expr_ir(node->data.binop.right);
        temp = new_temp_name();
        emit_ir("%s = %s %s %s", temp, left, op_to_text(node->data.binop.op), right);
        free(left);
        free(right);
        return temp;

    default:
        return copy_string("0");
    }
}

static void generate_stmt_ir(Node *node);

static void generate_list_ir(StmtList *list)
{
    while (list != NULL) {
        generate_stmt_ir(list->stmt);
        list = list->next;
    }
}

static void generate_stmt_ir(Node *node)
{
    char *value;
    char *label_start;
    char *label_end;

    if (node == NULL) {
        return;
    }

    switch (node->type) {
    case NODE_ASSIGN:
        value = generate_expr_ir(node->data.assign.value);
        emit_ir("%s = %s", node->data.assign.name, value);
        free(value);
        break;

    case NODE_PRINT:
        value = generate_expr_ir(node->data.print_stmt.expr);
        emit_ir("print %s", value);
        free(value);
        break;

    case NODE_EXPR_STMT:
        value = generate_expr_ir(node->data.expr_stmt.expr);
        emit_ir("eval %s", value);
        free(value);
        break;

    case NODE_IF:
        value = generate_expr_ir(node->data.if_stmt.cond);
        label_end = new_label_name();
        emit_ir("ifFalse %s goto %s", value, label_end);
        generate_stmt_ir(node->data.if_stmt.body);
        emit_ir("%s:", label_end);
        free(value);
        free(label_end);
        break;

    case NODE_WHILE:
        label_start = new_label_name();
        label_end = new_label_name();
        emit_ir("%s:", label_start);
        value = generate_expr_ir(node->data.while_stmt.cond);
        emit_ir("ifFalse %s goto %s", value, label_end);
        generate_stmt_ir(node->data.while_stmt.body);
        emit_ir("goto %s", label_start);
        emit_ir("%s:", label_end);
        free(value);
        free(label_start);
        free(label_end);
        break;

    case NODE_BLOCK:
        generate_list_ir(node->data.block.statements);
        break;

    default:
        break;
    }
}

static void generate_program_ir(void)
{
    ir_file = fopen("ir_output.txt", "w");
    if (ir_file == NULL) {
        fprintf(stderr, "Warning: could not create ir_output.txt\n");
        return;
    }

    ir_temp_counter = 1;
    ir_label_counter = 1;

    fprintf(ir_file, "# Three-address intermediate representation\n");
    generate_list_ir(program_statements);
    fclose(ir_file);
    ir_file = NULL;
}

static void exec_stmt(Node *node);

static void exec_list(StmtList *list)
{
    while (list != NULL) {
        exec_stmt(list->stmt);
        list = list->next;
    }
}

static void exec_stmt(Node *node)
{
    int value;
    int errors_before;

    if (node == NULL) {
        return;
    }

    switch (node->type) {
    case NODE_ASSIGN:
        errors_before = semantic_error_count;
        value = eval_expr(node->data.assign.value);
        if (semantic_error_count == errors_before) {
            set_symbol_value(node->data.assign.name, value);
        }
        break;

    case NODE_PRINT:
        errors_before = semantic_error_count;
        value = eval_expr(node->data.print_stmt.expr);
        if (semantic_error_count == errors_before) {
            printf("%d\n", value);
        }
        break;

    case NODE_EXPR_STMT:
        errors_before = semantic_error_count;
        value = eval_expr(node->data.expr_stmt.expr);
        if (semantic_error_count == errors_before) {
            printf("%d\n", value);
        }
        break;

    case NODE_IF:
        errors_before = semantic_error_count;
        value = eval_expr(node->data.if_stmt.cond);
        if (semantic_error_count == errors_before && value) {
            exec_stmt(node->data.if_stmt.body);
        }
        break;

    case NODE_WHILE:
        while (1) {
            errors_before = semantic_error_count;
            value = eval_expr(node->data.while_stmt.cond);
            if (semantic_error_count != errors_before || !value) {
                break;
            }
            exec_stmt(node->data.while_stmt.body);
        }
        break;

    case NODE_BLOCK:
        exec_list(node->data.block.statements);
        break;

    default:
        fprintf(stderr, "Internal error: invalid statement node\n");
        break;
    }
}
%}

%union {
    int ival;
    char *sval;
    Node *node;
    StmtList *list;
}

%token <ival> NUMBER
%token <sval> IDENTIFIER
%token PRINT IF WHILE
%token GE LE EQ NE
%token NEWLINE

%type <node> statement expression block
%type <list> lines line optional_last_statement

%left EQ NE '>' '<' GE LE
%left '+' '-'
%left '*' '/'
%right UMINUS

%%

program:
    lines optional_last_statement  { program_statements = list_concat($1, $2); }
    ;

lines:
    /* empty */                    { $$ = NULL; }
    | lines line                     { $$ = list_concat($1, $2); }
    ;

block:
    '{' lines optional_last_statement '}' { $$ = make_block(list_concat($2, $3)); }
    ;

line:
            separator                      { $$ = NULL; }
        | statement separator            { $$ = list_append(NULL, $1); }
    ;

optional_last_statement:
            /* empty */                    { $$ = NULL; }
        | statement                      { $$ = list_append(NULL, $1); }
    ;

separator:
    ';'
    | NEWLINE
    ;

statement:
      IDENTIFIER '=' expression      { $$ = make_assign($1, $3); free($1); }
    | PRINT expression               { $$ = make_print($2); }
    | IF '(' expression ')' statement { $$ = make_if($3, $5); }
    | WHILE '(' expression ')' statement { $$ = make_while($3, $5); }
    | block                          { $$ = $1; }
    | expression                     { $$ = make_expr_stmt($1); }
    ;

expression:
      expression '+' expression      { $$ = make_binop(OP_ADD, $1, $3); }
    | expression '-' expression      { $$ = make_binop(OP_SUB, $1, $3); }
    | expression '*' expression      { $$ = make_binop(OP_MUL, $1, $3); }
    | expression '/' expression      { $$ = make_binop(OP_DIV, $1, $3); }
    | expression '>' expression      { $$ = make_binop(OP_GT, $1, $3); }
    | expression '<' expression      { $$ = make_binop(OP_LT, $1, $3); }
    | expression GE expression       { $$ = make_binop(OP_GE, $1, $3); }
    | expression LE expression       { $$ = make_binop(OP_LE, $1, $3); }
    | expression EQ expression       { $$ = make_binop(OP_EQ, $1, $3); }
    | expression NE expression       { $$ = make_binop(OP_NE, $1, $3); }
    | '-' expression %prec UMINUS    { $$ = make_unary(OP_NEG, $2); }
    | '(' expression ')'             { $$ = $2; }
    | NUMBER                         { $$ = make_number($1); }
    | IDENTIFIER                     { $$ = make_variable($1); free($1); }
    ;

%%

void yyerror(const char *s)
{
    syntax_error_count++;
    fprintf(stderr, "Syntax error near line %d: %s\n", yylineno, s);
}

int main(void)
{
    if (yyparse() == 0 && syntax_error_count == 0) {
        generate_program_ir();
        exec_list(program_statements);

        if (semantic_error_count > 0) {
            fprintf(stderr, "Execution finished with %d semantic error(s).\n", semantic_error_count);
            return 1;
        }
        return 0;
    }

    return 1;
}
