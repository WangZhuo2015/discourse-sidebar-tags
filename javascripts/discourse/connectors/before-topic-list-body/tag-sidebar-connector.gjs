import Component from "@glimmer/component";
import { service } from "@ember/service";
import TagSidebar from "../../components/tag-sidebar";

console.log("--- [CONNECTOR] tag-sidebar-connector.gjs IS EXECUTING! ---");
export default class TagSidebarConnector extends Component {
  @service site;

  <template>
    {{#unless this.site.mobileView}}
      <TagSidebar />
    {{/unless}}
  </template>
}
