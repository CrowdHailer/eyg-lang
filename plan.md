Overlay needs to be able to produce and validate artifacts.
That is what this branch is demonstrating

Tasks

- [x] effect to create artifact
- [x] effect to show artifact
- [ ] implement the puppet pattern to control the artifact, see puppet.md
- [ ] implement a screenshot command for the artifact
- [ ] implement an EYG playwright library that follows the playwrite API but instead postsMessage to the puppet script inside the iframe.
- [ ] Do not use ffi in overlay_web or overlay_public instead add plinth (and gitignore) as a package and suggest changes to plinth.
- [ ] Compare and contrast the artifacts idea with the Spring 83 protocol.
- [ ] Add backend support in the hub for creating artifacts. /artifact/:uuid should show the artifact.
    - It should be possible to create artifacts locally without them ending up in the artifacts service.
    - When share is clicked they are transparently moved to the artifact service.
- [ ] Create a polished video. Mock responses from calls to ollama local. Create a test artifacts context with very strong modern design guidelines. the returned response should create a fresh modern crisp artifacts for everything it's showing. 
- [ ] Review the video, check it really is impressive and improve until it is.
- [ ] rework this branch in the following order
    - idependent fixes that could be merged without any features
    - Local artifacts
    - artifact control
    - remote and shared artifacts.