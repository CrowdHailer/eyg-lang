# Background workflow

I want to a agent use eyg to build a workflow that runs periodically.

The workflow must pull all new stories from lobsters.
Find all of those related to topics interesting to EYG, such as:
- new configuration languages
- effect types
- how much we dislike yaml
- new shells
- problems with bash, make
- structural typing

It track all relevant conversations and comments.
Every day it prioritises those that would be most interesting to engage with and write a file with
- the link to the conversation
- A summary of the article
- A summery of the comments
- Why I should be interested.

Given the above prompt an agent should.
- Build an agent SDK library in EYG
- write the workflow in EYG using that library
- write documentation explaining how that workflow is run
- suggest using railway.com as the place to run the workflow
- Explain how to deploy the workflow to railway.
- write a deploy script into entry.eyg in the workflow
- write tests that can be triggered from the entry.eyg script

