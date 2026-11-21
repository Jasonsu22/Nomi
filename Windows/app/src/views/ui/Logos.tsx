// Support/BrandLogo.swift and ProviderLogo.swift.
import appLogo from "../../assets/AppLogo.png";
import { Icon } from "./Icon";

const providers = import.meta.glob("../../assets/providers/*.{png,svg}", { eager: true, import: "default" }) as Record<string, string>;

export function BrandLogo({ side }: { side: number }) {
  return <img src={appLogo} width={side} height={side} draggable={false} alt="" style={{ objectFit: "contain" }} />;
}

export function ProviderLogo({ file, side = 16 }: { file: string | null | undefined; side?: number }) {
  const url = file ? Object.entries(providers).find(([path]) => path.includes(`/${file}.`))?.[1] : undefined;
  if (!url) return <Icon name="link" size={side * 0.7} className="text-[var(--text-2)]" />;
  const square = !url.includes("search-exa");
  return <img src={url} height={side} style={{ height: side, maxWidth: side * 4.6, borderRadius: square ? side * 0.22 : 0, objectFit: "contain", boxShadow: square ? "0 0 0 0.5px var(--separator)" : undefined }} draggable={false} alt="" />;
}
