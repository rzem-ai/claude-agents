  Still open, deliberately not touched

  - Steward scope. The compound skill, the runs README and the CLAUDE.md template still hand the steward a quarterly rules prune and the glossary republish that its body forbids, and its editing scope excludes CHANGELOG.md. You did not pick a direction on that one. Either widen the steward's scope and add
    a fifth job, or move both to the lead at compound time. Say which and I'll do it.
  - home/settings.json clobbers the live file. The install script copies, your live settings have 19 keys the repo does not know about, and zero deny entries today. Merge logic in the script is a code change, so I left it.
  - Two skills have diverging copies (using-memory across the agent-memory repos, alex-voice across angus and weekly-roundup). When you do move them in, one copy has to be declared canonical.
  - pr-review-toolkit is disabled in your live settings while the reviewer and the review-round workflow assume it ran.
  - The hooks README's own TODO stands. The docs do not settle status versus completion_reason or task_title versus task_name; confirm against a live hook input.
  - No git tags exist, so the changelog's compare links stay dead until v0.1.0 through v0.3.0 are tagged.
  