import { addFive } from ".";
import { describe, it, expect } from "vitest";

describe("addFive", () => {
  it("should add 5 to the input", () => {
    expect(addFive(10)).toBe(15);
  });
});
