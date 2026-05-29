# Onboarding review

The aim of this process is to give the most impactful and focused guidance to improve EYG in it's stated goals.
They are:

1. Be a safe, effective and ergonomic scripting language.
2. Support an flourishing ecosystem of packages.

You will try an onboarding path and track all difficulties, pain points and ambiguities when trying to get started with EYG.

## Prerequisits

Make sure your environment is clean. Remove all previous installations of the `eyg` CLI and any related skills/packages.

## Onboarding point

### Web search

A user has head about EYG and wants to try it out to solve a problem.
Act as that user's agent.

1. With no user input install EYG and check it is working.
2. Try common usecases for which the agent would write small scripts
3. Role play interaction with the user up through the levels of adoption below.

## Use case

### The "Hash-Based Toolbelt"
*   **Goal:** A collection of small utilities (JSON formatter, Timestamp converter, Base64 encoder) shared as EYG hash fragments.
*   **EYG Strength:** Content-addressed logic. No "npm install", just run the hash.
*   **Case Study:** "The Death of 'Scripts-as-Files': Content-Addressed Utilities for the Modern Developer."

## Adoption levels

1. User, or their agent, regularly uses eyg as their scripting substrate
1.a. User makes use of multiple authenticated integrations.
2. User shares scripts with their friends,
  - Sharing the hash fragment is an easy way to share something helpful.
3. User shares scripts with their colleague
4. User embeds EYG in their website
5. User reaches out to buy a package name

The user who has found EYG wants to replace all of their bash tools with EYG alternatives.
They are going to going to promote these tools on twitter and their blog.

They share lots as fragments on their website they have advise like

list all files using `eyg #baxxxxxx ./path/to/dir`

This user creates many small packages to tackle verbosity. they have helpers to decode json, work with CSV's
They don't call effects or builtins directly in their shared modules.

Role play this users journey all the way up to having a few 100 scripts they share and the articles they have written for it.

## Sandboxed testing

When testing sharing and publishing start a local development environment.
The CLI accepts EYG_ORIGIN as a way to point package resolution to a different hub.

## Reporting

Write a notes.md file at the top of the eyg-lang repo.

it should - track:
1. what did you do?
1.a. Add code snippets for all the usecases you tried.
2. What was difficult?
3. How pain points could be improved?
4. What was ambiguous? what descision did you have to make?
5. What features are needed?

in the notes - discuss:
- fixes for every pain point and feature improvement.
- prioritise by impact on the end user

Try implementing all the fixes identified above.
commit after every fix.
