# lesson_step.gd
#
# PURPOSE
#   One step of a guided lesson (README 7.6 mode 2): a prompt the student
#   reads, and optionally a check that must pass before "Next" unlocks.
#
# HOW IT FITS
#   A Lesson holds an Array[LessonStep]. LessonChecks evaluates `check` every
#   frame; main_screen.gd shows the step in the Lesson tab.
#   Valid check names are the keys of LessonChecks.CHECKS.
class_name LessonStep
extends Resource

## What the student should do, in one to three short sentences.
@export_multiline var prompt: String = ""
## "" = the student just presses Next. Otherwise a name from LessonChecks.CHECKS.
@export var check: String = ""
## The number the check compares against, in SI units (or %, s, cycles).
@export var check_value: float = 0.0
## Controls that become visible and usable from this step on (Lesson.CONTROL_NAMES).
@export var unlock_controls: Array[String] = []
