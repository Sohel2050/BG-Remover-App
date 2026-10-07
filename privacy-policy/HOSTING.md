# Hosting the privacy policy (free, via GitHub Pages)

You already have a GitHub repo for `update_config.json`
(`Sohel2050/Background-Remover-Controller`) — reuse it:

1. Fill in every `[TODO: ...]` placeholder in `privacy.html` (date,
   name/company, contact email).
2. Upload `privacy.html` to that repo's root (or a `docs/` folder — see
   step 3).
3. In the repo → **Settings → Pages**:
   - Source: "Deploy from a branch"
   - Branch: `main`, folder: `/ (root)` (or `/docs` if you put it there)
   - Save.
4. GitHub gives you a URL like:
   ```
   https://sohel2050.github.io/Background-Remover-Controller/privacy.html
   ```
   (This is already the exact URL set in `lib/services/app_links.dart`
   as `privacyPolicyUrl` — so once Pages is live, it just works. If you
   host it somewhere else instead, update that constant to match.)
5. Takes a few minutes to go live after enabling Pages. Test the URL in
   a browser before submitting to the Play Store — Play Console checks
   that the link actually resolves.

## Where you'll need to paste this URL
- Play Console → App content → Privacy policy
- App Store Connect → App Privacy → Privacy Policy URL
- Already wired into the app itself (Drawer → Privacy Policy, About screen)
