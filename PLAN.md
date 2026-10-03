# Ash support

Add EYG as a scripting language that can be used within the Ash framework

- homepage https://ash-hq.org/
- documentation https://ash.hexdocs.pm/readme.html

There is an existing ash_lua package that embeds Lua as a scripting language in Ash. https://ash-lua.hexdocs.pm/readme.html
We will follow the projects structure for components we need, however we will not need the same components.

Tasks:

- [ ] install the latest Elixir and erlang
- [ ] create an example erlang application. It should have a dynamic supervisor for counters that tick every 10 seconds
  - [ ] Create functions to `start_counter`, `set_tick_rate`, `get_value`, `shutdown`
  - [ ] Create an EYG effect for each of these. write the type and implementation in erlang.
  - [ ] Write a module counters_eyg that has `run` and `check` functions. These take a string which is EYG code, both type check the code in an environment with only the application effects available. pretty print any type errors. The run function then runs the changes
  - [ ] Create a video of joining the cluster and writing eyg scripts and executing them. Show that opening the obsever shows the new counter children and you can inspect there shape
    - first script, very simple single effect
    - second script, multiple effects
    - use the std library and create many effects
  - [ ] Write a blog post about embedding EYG in an erlang program, include the video
- [ ] Create the same counter example in Elixir, but in a phoenix application
  - [ ] There should be a script box on the homepage
  - [ ] The script box uses the textmate syntax highlighting
  - [ ] Use live view
      - [ ] Any program that parses has it's types checked, show errors on the page
      - [ ] Press enter or click submit to send the messages
  - [ ] create the same video of scripts and effects in this application
  - [ ] Write a blog post about embedding EYG in an Elixir program, include the video
- [ ] Create a package in this repo called ash_eyg
  - [ ] Implement The automatic creation of EYG effects from Ash constructs in the same way as for ash_lua
  - [ ] Show how to add just some of the effects to a eyg execution environment
  - [ ] Create a standard getting started ash project and show how to set up EYG to access the first domains and resources
  - [ ] Review and simplify the ash_eyg package
  - [ ] Create a video of setting up the project and installing EYG
  - [ ] Write a blog post about how to use EYG in Ash, be super focused on the technical steps