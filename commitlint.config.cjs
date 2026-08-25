module.exports = {
  extends: ['@commitlint/config-conventional'],

  rules: {
    // The repository squash-merges with squash_merge_commit_message = BLANK, so
    // the commit body of a pull request never reaches main. Failing a pull
    // request over the length of a body that is about to be discarded is what
    // blocks generated commits, whose bodies are lists of URLs that cannot
    // honour a 100 character limit.
    'body-max-line-length': [0, 'always', 100],
    'footer-max-line-length': [0, 'always', 100],
  },
};
