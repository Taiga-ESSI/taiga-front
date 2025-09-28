# Change Report — Taiga Front `feat/1/initial-custom`

## Executive Summary

* The communications lightbox that appeared during the project creation flow has been removed to prevent interruptions in the Final Year Project (TFG) academic environment.

## Details of Changes

### Communications Lightbox Disabled

* **File:** `app/modules/projects/create/create-project.controller.coffee`
* **Change:** The call to `@lightboxFactory.create("tg-newsletter-email-lightbox", ...)` within `displayOnPremise` has been commented out.
* **Reason:** During project creation, the dialog "Would you like to receive Taiga communications?" appeared. In our context, we do not collect consents for sending communications, so it has been removed to streamline the flow.
* **How to revert:** Uncomment the three corresponding lines to restore the lightbox.

## Verification

* No automated tests were executed (minimal visual change). Manual verification of project creation was performed, ensuring that the lightbox no longer appears.

## Files Affected

* `app/modules/projects/create/create-project.controller.coffee`
