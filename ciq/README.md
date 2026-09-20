# Jev Buddy CIQ data field

A playful Jev experiment for a personal Forerunner 265. A vector character changes color, face, and pose according to a Jev Choice: calm, steady, bouncy, or focused. This is not a fatigue or nutrition assessment.

Default `offline` mode cycles the four visual moods with a visible demo label and makes no requests. In `jev` mode, Garmin Connect on the phone connects directly to the TypeSafe API. No self-hosted relay is needed. The character is drawn locally without per-frame API calls.

`pnpm build:personal` reads gitignored `.personal.json` and `TYPESAFE_API_KEY` from the environment or `.env`. Its PRG contains the key and must not be distributed. Request interval: 30–600 seconds, default 60. Session budget: 1–120 attempts, default 120, including failures. Start with one attempt for a live API smoke test.

See the root README for setup and USB transfer. `pnpm build:ciq` makes a credential-free demo build. `pnpm test:ciq` runs Monkey C tests on the simulator without calling the real API. The PRG filename retains the original FuelGuide name.
