# Compiler Front-End Submission Guide

This folder is prepared as a clean submission package with only the core files needed for evaluation.

## Files in this folder

- `project.l`: Lexer rules (Flex)
- `project.y`: Parser + semantic actions + optional bonus code generation (Bison + C)
- `test_all_cases.txt`: One combined test file that includes all important test scenarios
- `CLAUDE_PDF_PROMPT.md`: Ready prompt to generate the final report PDF with Claude

## 1) Install Requirements (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y flex bison gcc
```

## 2) Build

Run these commands inside this folder:

```bash
bison -d project.y
flex project.l
gcc project.tab.c lex.yy.c -o project -lfl
```

## 3) Run (Combined Test File)

```bash
./project < test_all_cases.txt
```

This run may end with a non-zero exit code because the file intentionally includes error cases.

## 4) Check Optional Bonus IR Output

If the run is successful enough to generate IR, this file is created:

```bash
cat ir_output.txt
```

## 5) Quick Run with Only Valid Statements (Optional)

If you want a clean success run, use only the valid sections from `test_all_cases.txt` in a temporary input file.
