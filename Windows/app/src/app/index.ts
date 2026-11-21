// The app model with all its features, and the React hook that redraws on change.
import { useSyncExternalStore } from "react";
import { AppModel } from "./model";
import "./chat";
import "./chatQueue";
import "./afterAnswer";
import "./assistant";
import "./voices";
import "./qa";
import "./citations";
import "./onboarding";

export { AppModel };
export const model = new AppModel();

/** Re-renders the calling component whenever the model changes. */
export function useModel(): AppModel {
  useSyncExternalStore(
    (listener) => model.subscribe(listener),
    () => model.version,
  );
  return model;
}
