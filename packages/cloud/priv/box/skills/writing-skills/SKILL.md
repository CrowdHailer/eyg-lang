---
name: writing-skills
description: How to write a new skill, or improve one, for agents working in this box. Use it when you are asked to make a skill, or when you have worked out a procedure that is worth reusing.
---

# Writing skills

A skill is a directory in `/skills` with a `SKILL.md` file.
Agents list `/skills` when they start a task and read the `SKILL.md` of each skill that matches it.

## Layout

```
/skills/<name>/SKILL.md   the skill, required
/skills/<name>/...        files the skill uses, such as EYG modules or examples
```

`<name>` is lowercase words joined with dashes, such as `send-email`.

## SKILL.md

It starts with frontmatter:

```
---
name: <name>
description: <what the skill does and when to use it>
---
```

The description is all an agent reads when deciding whether to use the skill, so say when it applies, in one or two sentences.

The body is instructions for an agent that has never seen this box:
the steps to take, the effects and packages to use, short EYG examples and how to check the result.
Keep it short, put longer examples in other files in the skill's directory and say when to read them.

## Steps

1. List `/skills` with the `ReadDirectory` effect, update an existing skill rather than adding one that overlaps it.
2. Write the steps that worked, not every step that was tried.
3. Put reusable code in an EYG module beside the skill, such as `/skills/<name>/helper.eyg`.
   Every `.eyg` file in the box must type check, so a module that does not is rejected.
   Code uses it with `import "/skills/<name>/helper.eyg"`.
4. Make the directory with the `MakeDirectory` effect and write each file with the `WriteFile` effect.
5. Read the skill back and check that the description says when to use it and that the steps can be followed as written.
