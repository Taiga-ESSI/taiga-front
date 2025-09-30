# Change Report — Taiga Front `feat/1/initial-custom`

## Executive Summary

* The communications lightbox that appeared during the project creation flow has been removed to prevent interruptions in the Final Year Project (TFG) academic environment.
* Custom field save buttons remain visible at all times to avoid hover-only discovery issues.
* The default project creation entry point now redirects to the Scrum template for faster setup.

## Details of Changes

### Communications Lightbox Disabled

* **File:** `app/modules/projects/create/create-project.controller.coffee`
* **Change:** The call to `@lightboxFactory.create("tg-newsletter-email-lightbox", ...)` within `displayOnPremise` has been commented out.
* **Reason:** During project creation, the dialog "Would you like to receive Taiga communications?" appeared. In our context, we do not collect consents for sending communications, so it has been removed to streamline the flow.
* **How to revert:** Uncomment the three corresponding lines to restore the lightbox.
* **Author:** Pol Alcoverro.

### Custom Field Save Button Always Visible

* **File:** `app/styles/modules/common/custom-fields.scss`
* **Change:** Set `.custom-field-options` to `opacity: 1` (and left the previous `opacity: 0` commented) so the save button is always displayed.
* **Reason:** Prevents users from missing the hover-only control when editing custom fields.
* **How to revert:** Remove the inline comment and reinstate `opacity: 0` if hover-only behaviour is desired.
* **Author:** Pol Alcoverro.

### Project Creation Redirects to Scrum Template

* **File:** `app/coffee/app.coffee`
* **Change:** Replaced the `/project/new` route definition with a redirect to `/project/new/scrum`, leaving the previous configuration commented for traceability.
* **Reason:** The Scrum template is the default for our workflows, so bypassing the intermediate selector accelerates onboarding.
* **How to revert:** Uncomment the original route definition and remove the redirect.
* **Author:** Pol Alcoverro.

## Verification

* No automated tests were executed (minimal visual change). Manual verification of project creation was performed, ensuring that the lightbox no longer appears.

## Files Affected

* `app/modules/projects/create/create-project.controller.coffee`
* `app/styles/modules/common/custom-fields.scss`
* `app/coffee/app.coffee`
