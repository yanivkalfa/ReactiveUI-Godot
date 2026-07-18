import { test } from "node:test";
import assert from "node:assert";
import { classifyContext } from "../context";

test("tag-name position after <", () => {
  const src = "component X() { return ( <La";
  assert.equal(classifyContext(src, src.length).kind, "tagName");
});

test("attribute-name position inside an open tag", () => {
  const src = "component X() { return ( <Label te";
  const ctx = classifyContext(src, src.length);
  assert.equal(ctx.kind, "attrName");
  assert.equal(ctx.tag, "Label");
});

test("attribute value {expr} is embedded", () => {
  const src = "component X() { return ( <Label text={ co";
  assert.equal(classifyContext(src, src.length).kind, "embedded");
});

test("directive after @ in markup", () => {
  const src = "component X() { return ( <VBox>\n\t@i";
  const ctx = classifyContext(src, src.length);
  assert.equal(ctx.kind, "directive");
  assert.equal(ctx.word, "@i");
});

test("setup line is embedded", () => {
  const src = "component X() {\n\tvar s = use_st";
  assert.equal(classifyContext(src, src.length).kind, "embedded");
});

test("child {expr} is embedded", () => {
  const src = "component X() { return ( <VBox>{ coun";
  assert.equal(classifyContext(src, src.length).kind, "embedded");
});
