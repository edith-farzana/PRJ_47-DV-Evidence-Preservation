# Setting up Firebase for Secure Evidence

**Who this is for:** whoever is doing the Firebase setup. You do not need to
write any code — all the code is already written and committed. This is
clicking through a website, running a handful of commands, and checking that
the right things happened.

**How long it takes:** about 45–60 minutes, most of it waiting for things to
finish.

**If you get stuck at any point, stop and message Akash rather than guessing.**
One wrong choice here (see §2.2) can leave the database open to the internet,
and that is the one mistake worth being careful about.

---

## What you are actually setting up, in plain words

The app stores evidence on the phone, encrypted. This setup adds a server that
does one job: **keep a permanent, unchangeable record that a piece of evidence
existed.**

Three pieces:

| Piece | What it does here |
|---|---|
| **Authentication** | Gives each phone an anonymous ID. No email, no phone number — an abuser must not be able to spot a confirmation message in her inbox |
| **Firestore** | A database holding one small record per piece of evidence: its fingerprint, a timestamp, a size. No filenames, no photos, nothing readable |
| **Storage** | Holds the encrypted files themselves — but only for items the survivor specifically chooses to back up |

The important part is a rule we have already written: **once a record is
created, nobody can change or delete it.** Not the survivor, not us, not
someone who steals her phone. The server refuses. That is the thing we
demonstrate in the review, and your job is to make it real.

### A few words you will see

- **Project** — your container for all of this on Google's side.
- **Rules** — the file that says who may read and write what. Ours are already
  written: `firestore.rules` and `storage.rules` in the repo.
- **Emulator** — a fake Firebase that runs on your laptop, so we can test the
  rules without touching the real thing.
- **uid** — the anonymous ID given to a phone.

---

## Before you start

You need a Google account you are happy to own this project, and the repo on
your machine on the branch `feature/p4-safety-fixes`.

Check the tools are installed. Run each line; each should print a version
rather than "command not found":

```bash
flutter --version
```

```bash
firebase --version
```

```bash
node --version
```

```bash
java -version
```

- **Missing `flutter`?** You need the Flutter SDK. Ask Akash — he has notes on
  how it was installed.
- **Missing `firebase`?** Install it with `npm install -g firebase-tools`.
- **Missing `java`?** Only needed for §6 (the emulator). You can do everything
  else without it.

One more, which installs the FlutterFire helper:

```bash
dart pub global activate flutterfire_cli
```

---

## 1. Sign in

```bash
firebase login
```

A browser window opens. Sign in with the Google account you want to own the
project, and allow the permissions it asks for. When it says you are logged in,
come back to the terminal.

Check it worked:

```bash
firebase projects:list
```

You should get a table (it may be empty — that is fine).

---

## 2. Create the project

Go to **https://console.firebase.google.com** and click **Create a project**.

### 2.1 Name it

Call it something like `secure-evidence`. Google will add random characters to
make the ID unique — that is normal. **Write the full project ID down**; you
need it later.

You can turn Google Analytics **off**. We do not use it, and it is one less
thing collecting data about people using this app.

### 2.2 Turn on Firestore — read this bit carefully

In the left menu: **Build → Firestore Database → Create database**.

Two questions:

**Location.** Pick one close to you — `asia-south1` (Mumbai) is a good choice
for India. ⚠️ **This cannot be changed later.**

**Security rules.** You will be offered **production mode** and **test mode**.

> ### Choose production mode.
>
> Test mode makes the entire database readable and writable **by anyone on the
> internet** for 30 days. For an app holding evidence about domestic violence,
> that is not a small mistake. Production mode starts locked, and we replace
> the rules with our own in §5.
>
> If you pick the wrong one by accident it is fixable — just tell Akash and
> carry on, do not try to hide it.

### 2.3 Turn on Anonymous sign-in

**Build → Authentication → Get started**, then the **Sign-in method** tab.

Find **Anonymous** in the list, click it, switch it **on**, and save.

Do **not** enable Email, Google, or phone sign-in. Anonymous is a deliberate
safety decision: anything that sends a confirmation message creates a trace in
an inbox an abuser might be able to read.

### 2.4 Turn on Storage

**Build → Storage → Get started**. Take the same location as Firestore, and
again choose **production mode** if it asks.

> **If it asks you to upgrade to the Blaze plan:** Firebase now requires
> billing to be enabled before Storage can be turned on, even though the free
> allowance still covers everything we need.
>
> You have two options, and **both are fine — check with Akash before adding a
> card**:
>
> 1. Add a billing account. The free tier is generous and our usage is tiny.
>    Set a budget alert at a low number if it makes you more comfortable.
> 2. **Skip Storage entirely.** Everything else still works: every piece of
>    evidence still gets its permanent record, and the demo of "delete is
>    denied" still works exactly the same. The only thing missing is uploading
>    the encrypted files themselves. If you skip it, tell Akash so the app can
>    be set to not offer backup.

---

## 3. Connect the app to the project

From the repo folder:

```bash
flutterfire configure
```

It will ask:

1. **Which project?** Use arrow keys to pick the one you just created.
2. **Which platforms?** Select **android** only. Use the space bar to
   tick/untick, then Enter. Untick ios, web, macos, windows — we only ship
   Android.

When it finishes it will have created two files. Check they exist:

```bash
ls -l android/app/google-services.json lib/firebase_options.dart
```

Both should be listed. If either is missing, the step did not finish — run it
again and watch for an error message.

### 3.1 Check it did not break the build

```bash
flutter build apk --debug
```

This takes a few minutes the first time. It should end with `✓ Built ...`.

> **If it fails with a message about `google-services` or the Gradle plugin**,
> copy the whole error and send it to Akash. There is a line that sometimes
> needs adding to `android/app/build.gradle.kts` by hand, and he will tell you
> exactly what to paste.

### 3.2 Link the folder to the project

So the next command knows where to deploy:

```bash
firebase use --add
```

Pick your project, and when it asks for an alias just type `default`.

---

## 4. Do not commit the secret files

`google-services.json` and `firebase_options.dart` identify your project and
must stay off GitHub. They are already listed in `.gitignore`, so git should
ignore them automatically. Confirm:

```bash
git status --short
```

**Neither file should appear in that list.** If either one does, stop and tell
Akash before committing anything.

---

## 5. Deploy the rules

This is the important one. It uploads the two rule files from the repo to your
project, replacing the locked-down defaults.

```bash
firebase deploy --only firestore:rules,storage
```

You should see `✔ Deploy complete!`.

Now look at them in the console: **Firestore Database → Rules**. You should see
our file, including this line:

```
allow update, delete: if false;   // nobody, ever -- including the owner
```

If you still see something about `request.time < timestamp.date(...)`, the old
default rules are still there — the deploy did not work. Check for an error
message and try again.

---

## 6. Test the rules (needs Java)

This runs a fake Firebase on your laptop and checks the rules really do refuse
what they are supposed to refuse. **It never touches your real project.**

Install the test dependencies once:

```bash
npm --prefix test/rules install
```

Then run the tests:

```bash
firebase emulators:exec --only auth,firestore,storage "npm --prefix test/rules test"
```

You want to see a list of ticks and `15 passing`, including lines like
**"UPDATING a record is denied, even for its owner"** and **"DELETING a record
is denied, even for its owner"**.

If anything fails, copy the whole output and send it over. A failure here is
genuinely useful information, not a mistake on your part — it means a rule does
not do what we think it does.

---

## 7. See it working on a phone

Install the app on a real Android phone (`flutter run`, or build an APK and
copy it across), then:

1. Open the app, set a PIN and an unlock sequence.
2. Take a photo through the app.
3. Open **My Evidence** — the photo should be listed, marked `ENCRYPTED` and
   `THIS PHONE ONLY`.

Now look in the console at **Firestore Database → Data**. You should see:

```
users → (a long random id) → evidence → (another long id)
```

Open that record. **This is the bit worth looking at properly.** You should see
only hashes, a date, a size and a type. No filename, no photo, nothing that
says who this is. That is the whole design: we hold proof the evidence exists,
and nothing that could hurt her if it leaked.

Check **Storage** as well: it should be **empty**. Nothing is uploaded unless
she asks.

Then, in the app, open the photo and tap **Back up this evidence**. Refresh the
console:

- **Storage** now has one `.enc` file. Download it and try to open it — it will
  not open in any photo viewer. That is correct; it is encrypted.
- **Firestore** now has a second collection, `backups`, with a receipt.

---

## 8. The moment for the review

This is what gets demonstrated, so get a screenshot of it.

In the console: **Firestore Database → Rules → Rules Playground**.

1. Set the simulation type to **delete**.
2. In the location box, paste the path of the evidence record you saw in §7 —
   something like `/users/abc123.../evidence/def456...`.
3. Turn **Authenticated** on, and put that same user id in the Firebase UID
   box, so you are simulating the owner herself.
4. Click **Run**.

It should say **Simulated read/write denied**.

Take a screenshot. That is the claim the whole project rests on: not "our app
does not offer a delete button", but "the server refuses, even to the person
who created it, even with her own credentials".

Try it again with **update** as well. Same result. Screenshot that too.

---

## When you are done, send back

- The **project ID**.
- A screenshot of the rules playground showing **delete denied**.
- Whether you enabled Storage or skipped it (§2.4).
- Anything that failed, with the full error text.

Do **not** send the `google-services.json` file over chat or email — it is not
a password, but it belongs in the project folder, not in a message.

---

## If something goes wrong

| What you see | What it means | What to do |
|---|---|---|
| `Failed to authenticate, have you run firebase login?` | Your login expired | Run `firebase login` again |
| `No currently active project` | The folder is not linked to the project | Run `firebase use --add` (§3.2) |
| `Permission denied` in the app when capturing | The rules are not deployed, or anonymous sign-in is off | Redo §2.3 and §5 |
| `Default FirebaseApp is not initialized` | `google-services.json` is missing | Redo §3, and check the file exists |
| Emulator command hangs or says `java: not found` | Java is not installed | Install a JDK, or hand §6 to Akash |
| Build fails mentioning `minSdk` | Firebase needs a newer Android minimum | Tell Akash — it is a one-line change |
| Storage asks for a credit card | Firebase requires billing for Storage now | See the box in §2.4 — check before adding a card |

## Things to avoid

- **Do not** set any rule to `allow read, write: if true`. If something is not
  working, that will "fix" it by removing the only protection this system has.
- **Do not** enable email or phone sign-in.
- **Do not** commit `google-services.json` or `firebase_options.dart`.
- **Do not** delete or edit `firestore.rules` / `storage.rules` — if they seem
  wrong, that is worth a conversation, not a quiet edit.
- **Do not** put real evidence, or anything about a real person, into the app
  while testing. Photograph a wall.
