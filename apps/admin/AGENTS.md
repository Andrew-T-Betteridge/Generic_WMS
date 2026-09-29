<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Project architecture

- The Lovable implementation is authoritative for Admin frontend visuals and UX; preserve its rendered appearance when integrating repository source.
- The external DYNETIC Generic WMS API and Auth0 are authoritative for data, permissions, security, and business actions; never duplicate or replace them in this frontend.
