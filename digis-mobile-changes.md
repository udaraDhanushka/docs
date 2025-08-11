Overview

    I'll implement the conditional download button feature by modifying the type
     definitions and the TenantAttachmentsBottomSheet component to check for a 
    downloadable attribute in the file metadata.

    Files to Modify

    1. src/configs/types/metadataTypes.ts

    - Add optional downloadable property to AttachmentFile interface
    - Default behavior: If downloadable is undefined, treat as false (hide 
    download button)

    export interface AttachmentFile {
      file_name: string;
      url: string;
      downloadable?: boolean;  // New optional property
    }

    2. src/components/TenantAttachmentsBottomSheet/index.tsx

    - Update AttachmentItemProps to include isDownloadable property
    - Modify AttachmentItem component to conditionally render download button
    - Pass downloadable flag from file data to AttachmentItem
    - Adjust styling to maintain clean layout when button is hidden

    Key Changes

    AttachmentItem Component:

    - Add isDownloadable?: boolean prop (optional with default false)
    - Conditionally render the download container based on this prop
    - When download is disabled, the file will still be viewable (tap to 
    preview)

    Parent Component Logic:

    - Extract downloadable property from file data
    - Pass it to AttachmentItem component
    - Handle backwards compatibility (undefined = false)

    Implementation Details

    1. Type Safety: The downloadable property will be optional to maintain 
    backwards compatibility
    2. Default Behavior: Files without the attribute will default to 
    non-downloadable
    3. UI Consistency: The layout will remain clean whether button is shown or 
    hidden
    4. Functionality: Preview functionality remains unchanged for all files

    Testing Considerations

    - Files with downloadable: true → Show download button
    - Files with downloadable: false → Hide download button  
    - Files without downloadable property → Hide download button (backwards 
    compatible)
    - All files remain viewable through tap action

    Benefits

    - Clean implementation with minimal changes
    - Backwards compatible with existing data
    - Maintains all existing functionality
    - Clear separation of concerns

################## Changes has been pushed - 25-08-11 ##################