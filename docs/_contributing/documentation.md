---
template: default
title: Documentation
---
## Adding and updating AIS Charts documentation

NB: This is for Public facing documents.

All MarkDown documents located under the `docs' folder in the root of the repo will be published to a public site at {{ site.url }}.

If you are adding a new document create a file with a .md extension.

Add to Jekyll Page index, add a YAML front matter block

```
---
template: default
title: "Title of Page"
---
add your markdown here
```

The front matter YAML will tell Jekyll that this is a page to publish, the template to use for CSS, etc, and the Title to use in links and page headings.

Thats it!

NB: Only documentation within the main branch will be published to the official AIS Charts Pages.
