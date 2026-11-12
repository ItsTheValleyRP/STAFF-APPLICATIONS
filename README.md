# The Valley — Staff Recruitment Center

Standalone Staff application website for The Valley Roleplay.

## Features
- Discord sign-in through the existing Supabase Auth provider
- Staff-only application form with the requested eight questions
- Applicant-only application status and reviewer feedback
- Staff review queue for authorized reviewers
- Uses the existing Valley application tables and portal RPCs
- No changes to the main VALLEY website or other department websites

## Deployment
1. Open this repository's **Settings → Pages**.
2. Under Build and deployment, choose **Deploy from a branch**.
3. Select branch **main** and folder **/(root)**, then Save.
4. The expected site URL is: https://itsthevalleyrp.github.io/STAFF-APPLICATIONS/

## Supabase
This website connects to the existing Valley Supabase project. In Supabase → Authentication → URL Configuration, add this exact URL to **Redirect URLs**:

`https://itsthevalleyrp.github.io/STAFF-APPLICATIONS/`

Keep the existing Discord OAuth provider configuration. The frontend uses the Supabase publishable key only. Never add a service-role key to this repository.

Run `supabase/staff_form_setup.sql` in Supabase SQL Editor to set the Staff form definition to the requested eight questions. This is an additive form-only update; it does not delete or modify existing application submissions.

## Existing backend requirement
The site calls the existing `valley_portal_get_my_roles`, `valley_portal_submit_application`, and `valley_portal_review_application` RPCs and reads Staff-scoped rows from `valley_applications`. Staff review access must be granted by the existing Supabase permissions/policies. Do not reset the project or delete existing tables/functions.
