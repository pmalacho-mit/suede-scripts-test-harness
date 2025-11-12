import { add, subtract, multiply, divide, exponentiate, square } from "./index";
import { expect, test } from "vitest";

test("adds 1 + 2 to equal 3", () => {
  expect(add(1, 2)).toBe(3);
});

test("subtracts 5 - 2 to equal 3", () => {
  expect(subtract(5, 2)).toBe(3);
});

test("multiplies 3 * 4 to equal 12", () => {
  expect(multiply(3, 4)).toBe(12);
});

test("divides 10 / 2 to equal 5", () => {
  expect(divide(10, 2)).toBe(5);
});

test("exponentiates 2 ** 3 to equal 8", () => {
  expect(exponentiate(2, 3)).toBe(8);
});

test("squares 4 to equal 16", () => {
  expect(square(4)).toBe(16);
});
