-- The Valley Staff Recruitment Center
-- Safe, additive form update: changes only the Staff form definition.
-- Existing applications, answers, roles, and audit records are not deleted or modified.

begin;

insert into public.valley_application_forms
  (department, title, description, questions, is_open, updated_at)
values
  ('staff',
   'VALLEY Staff Application',
   'Apply to join The Valley Roleplay staff team.',
   '[
     {"key":"discord_username","label":"Discord Username (Example: Name#0001)","type":"text","required":true},
     {"key":"steam_name","label":"What is your Steam name?","type":"text","required":true},
     {"key":"character_name","label":"What''s your in-game character name?","type":"text","required":true},
     {"key":"age","label":"How old are you?","type":"text","required":true},
     {"key":"staff_experience","label":"Do you have any prior Staff experience? If so please explain.","type":"textarea","required":true},
     {"key":"team_qualities","label":"What would make you a good addition to our team? And What qualities can you bring to our staff team?","type":"textarea","required":true},
     {"key":"weekly_hours","label":"How many hours can you put into discord/city per week?","type":"text","required":true},
     {"key":"about_yourself_ooc","label":"Tell us about yourself. (OOC)","type":"textarea","required":true}
   ]'::jsonb,
   true,
   now())
on conflict (department) do update
set title = excluded.title,
    description = excluded.description,
    questions = excluded.questions,
    updated_at = now();

commit;

-- NOTE:
-- This migration does not change permissions or create new RPCs.
-- The site uses the existing valley_portal_* application functions.
-- Staff reviewer permissions must already be granted by the existing portal
-- database policies/functions for Staff-scoped applications.
