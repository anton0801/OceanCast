<?php

declare(strict_types=1);

namespace OceanCast\Core;

/**
 * Whitelist validation. Anything not described here never reaches the database:
 * unknown keys are dropped, types are coerced explicitly, lengths are bounded.
 */
final class Validator
{
    /** @var array<string,string> */
    private array $errors = [];
    /** @var array<string,mixed> */
    private array $clean = [];

    /** @param array<string,mixed> $input */
    public function __construct(private readonly array $input)
    {
    }

    public function string(string $key, bool $required, int $min = 0, int $max = 255, ?string $pattern = null): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw)) {
            $this->errors[$key] = 'This field must be text.';
            return $this;
        }

        $value = trim($raw);
        // Strip control characters that have no business in stored text.
        $value = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $value) ?? '';

        $length = mb_strlen($value);
        if ($length < $min) {
            $this->errors[$key] = "Must be at least {$min} characters.";
            return $this;
        }
        if ($length > $max) {
            $this->errors[$key] = "Must be at most {$max} characters.";
            return $this;
        }
        if ($pattern !== null && !preg_match($pattern, $value)) {
            $this->errors[$key] = 'This value has an unexpected format.';
            return $this;
        }

        $this->clean[$key] = $value;
        return $this;
    }

    public function email(string $key, bool $required = true): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw)) {
            $this->errors[$key] = 'This field must be text.';
            return $this;
        }
        $value = strtolower(trim($raw));
        if (mb_strlen($value) > 255 || filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
            $this->errors[$key] = 'Enter a valid email address.';
            return $this;
        }
        $this->clean[$key] = $value;
        return $this;
    }

    /** Password rules are enforced server-side, never only in the app. */
    public function password(string $key, bool $required = true): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw)) {
            $this->errors[$key] = 'This field must be text.';
            return $this;
        }
        $length = strlen($raw);
        if ($length < 10) {
            $this->errors[$key] = 'Use at least 10 characters.';
            return $this;
        }
        if ($length > 200) {
            $this->errors[$key] = 'Use at most 200 characters.';
            return $this;
        }
        if (!preg_match('/[A-Za-z]/', $raw) || !preg_match('/\d/', $raw)) {
            $this->errors[$key] = 'Include at least one letter and one digit.';
            return $this;
        }
        $this->clean[$key] = $raw;
        return $this;
    }

    public function number(string $key, bool $required, float $min = -1e12, float $max = 1e12): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_numeric($raw)) {
            $this->errors[$key] = 'This field must be a number.';
            return $this;
        }
        $value = (float) $raw;
        if ($value < $min || $value > $max) {
            $this->errors[$key] = "Must be between {$min} and {$max}.";
            return $this;
        }
        $this->clean[$key] = $value;
        return $this;
    }

    public function integer(string $key, bool $required, int $min = 0, int $max = 1000000): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_numeric($raw) || (int) $raw != $raw) {
            $this->errors[$key] = 'This field must be a whole number.';
            return $this;
        }
        $value = (int) $raw;
        if ($value < $min || $value > $max) {
            $this->errors[$key] = "Must be between {$min} and {$max}.";
            return $this;
        }
        $this->clean[$key] = $value;
        return $this;
    }

    public function boolean(string $key, bool $required = false): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null) {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        $this->clean[$key] = filter_var($raw, FILTER_VALIDATE_BOOL, FILTER_NULL_ON_FAILURE) ?? false;
        return $this;
    }

    /** @param string[] $allowed */
    public function enum(string $key, array $allowed, bool $required): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw) || !in_array($raw, $allowed, true)) {
            $this->errors[$key] = 'Allowed values: ' . implode(', ', $allowed) . '.';
            return $this;
        }
        $this->clean[$key] = $raw;
        return $this;
    }

    public function uuid(string $key, bool $required): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw) || !Uuid::isValid($raw)) {
            $this->errors[$key] = 'This must be a UUID.';
            return $this;
        }
        $this->clean[$key] = Uuid::normalize($raw);
        return $this;
    }

    /** ISO-8601 timestamp or a plain date. */
    public function dateTime(string $key, bool $required): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw)) {
            $this->errors[$key] = 'This must be a date.';
            return $this;
        }
        $timestamp = strtotime($raw);
        if ($timestamp === false) {
            $this->errors[$key] = 'This must be an ISO-8601 date.';
            return $this;
        }
        $this->clean[$key] = gmdate('Y-m-d H:i:s', $timestamp);
        return $this;
    }

    public function date(string $key, bool $required): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null || $raw === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_string($raw)) {
            $this->errors[$key] = 'This must be a date.';
            return $this;
        }
        $timestamp = strtotime($raw);
        if ($timestamp === false) {
            $this->errors[$key] = 'This must be an ISO-8601 date.';
            return $this;
        }
        $this->clean[$key] = gmdate('Y-m-d', $timestamp);
        return $this;
    }

    /** Structured JSON payload (meal ingredients, catalogue hints, recall codes). */
    public function jsonValue(string $key, bool $required, int $maxBytes = 65535): self
    {
        $raw = $this->input[$key] ?? null;
        if ($raw === null) {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $this;
        }
        if (!is_array($raw)) {
            $this->errors[$key] = 'This field must be a JSON object or array.';
            return $this;
        }
        $encoded = json_encode($raw, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($encoded === false || strlen($encoded) > $maxBytes) {
            $this->errors[$key] = 'This structure is too large.';
            return $this;
        }
        $this->clean[$key] = $encoded;
        return $this;
    }

    public function fails(): bool
    {
        return $this->errors !== [];
    }

    /** @return array<string,string> */
    public function errors(): array
    {
        return $this->errors;
    }

    /** @return array<string,mixed> */
    public function validated(): array
    {
        if ($this->fails()) {
            throw ApiException::validation('Some fields need attention.', $this->errors);
        }
        return $this->clean;
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, $this->input);
    }
}
