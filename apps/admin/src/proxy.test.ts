import { EMAIL_WORDMARK_PATH } from "@repo/contracts";
import { unstable_doesMiddlewareMatch } from "next/experimental/testing/server";
import { describe, expect, it } from "vitest";
import { config } from "./proxy";

/**
 * The login redirect must not catch the brand assets (ADR-032 §2): the browser
 * fetches the favicon before any session exists, and an email client never has
 * the session cookie when it loads the email header image.
 */
describe("proxy matcher", () => {
  it.each(["/icon.png", EMAIL_WORDMARK_PATH])("lets %s through without a session", (url) => {
    expect(unstable_doesMiddlewareMatch({ config, url })).toBe(false);
  });

  it.each(["/", "/activities", "/users/u1"])("still guards the backoffice page %s", (url) => {
    expect(unstable_doesMiddlewareMatch({ config, url })).toBe(true);
  });
});
