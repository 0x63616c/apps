"use client";

import { useActionState, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { login } from "@/server/actions";

export function LoginForm({ next }: { next: string }) {
  const [state, action, pending] = useActionState(login, null);
  const [email, setEmail] = useState("");
  const failed = state?.ok === false;
  return (
    <Card className="w-full max-w-sm">
      <CardHeader>
        <CardTitle className="text-lg">Log in</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={action}>
          <input type="hidden" name="next" value={next} />
          <FieldGroup>
            {failed && (
              <Alert variant="destructive">
                <AlertDescription>{state.error}</AlertDescription>
              </Alert>
            )}
            <Field data-invalid={failed || undefined}>
              <FieldLabel htmlFor="email">Email</FieldLabel>
              <Input
                id="email"
                name="email"
                type="email"
                autoComplete="username"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoFocus
                aria-invalid={failed || undefined}
              />
            </Field>
            <Field data-invalid={failed || undefined}>
              <FieldLabel htmlFor="password">Password</FieldLabel>
              <Input
                id="password"
                name="password"
                type="password"
                autoComplete="current-password"
                required
                aria-invalid={failed || undefined}
              />
            </Field>
            <Button type="submit" className="w-full" disabled={pending}>
              {pending && <Spinner data-icon="inline-start" />}
              Continue
            </Button>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  );
}
