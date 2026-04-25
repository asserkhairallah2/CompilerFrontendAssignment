# Compiler Front-End Project

This project is a student-level compiler front-end built using Flex and Bison.
It supports lexical analysis, syntax analysis, semantic checks, and execution of a mini language.

## Project Summary

The language supports:

- Arithmetic expressions: +, -, *, /
- Variables and assignment
- print statements
- Conditional execution with if
- Repetition with while

Semantic error handling includes:

- Undefined variable usage
- Division by zero
- Identifier length validation (bonus semantic check)

Bonus feature:

- Simple three-address Intermediate Representation (IR) generation in ir_output.txt

## Technologies Used

- Flex (Lex) for tokenization
- Bison (Yacc) for parsing
- C actions inside Bison grammar for execution and semantic checks

## Files

- project.l: Lexer rules
- project.y: Parser grammar + semantic actions + runtime execution
- test_all_cases.txt: Combined test input that includes valid and error scenarios
- ir_output.txt: Generated IR output after running the program
- Compiler_FrontEnd_Report.pdf: Final project report
- Photo_1.png: Installation/build screenshot
- Photo_2.png: Code screenshot
- Photo_3.png: Runtime output screenshot

## Installation (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y flex bison gcc
```

## Build Steps

Run inside this folder:

```bash
bison -d project.y
flex project.l
gcc project.tab.c lex.yy.c -o project -lfl
```

## Run

Use the combined test file:

```bash
./project < test_all_cases.txt
```

Note:
- This file intentionally contains semantic error cases.
- Because of that, the program may finish with a non-zero exit code.

## Check Generated IR (Bonus)

```bash
cat ir_output.txt
```

## Quick Verification

Expected valid outputs from the valid sections include:

- 8
- 16
- 4
- 5
